-- ICT371 QUESTION 8: TRANSPORT FLEET MAINTENANCE
DROP SCHEMA IF EXISTS q8_transport CASCADE;
CREATE SCHEMA q8_transport;
SET search_path TO q8_transport;

CREATE TABLE vehicles(
 vehicle_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 registration VARCHAR(20) NOT NULL UNIQUE,
 current_odometer NUMERIC(12,1) NOT NULL CHECK(current_odometer>=0),
 last_service_odometer NUMERIC(12,1) NOT NULL CHECK(last_service_odometer>=0 AND last_service_odometer<=current_odometer)
);
CREATE TABLE trips(
 trip_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 vehicle_id BIGINT NOT NULL REFERENCES vehicles(vehicle_id),
 trip_on DATE NOT NULL,start_odometer NUMERIC(12,1) NOT NULL,
 end_odometer NUMERIC(12,1) NOT NULL,
 CHECK(start_odometer>=0 AND end_odometer>start_odometer)
);
CREATE TABLE service_alerts(
 vehicle_id BIGINT PRIMARY KEY REFERENCES vehicles(vehicle_id),
 km_since_service NUMERIC(12,1) NOT NULL,flagged_on DATE NOT NULL
);
INSERT INTO vehicles(registration,current_odometer,last_service_odometer) VALUES
('ABC001',10000,6000),('ABC002',20000,15000),('ABC003',5000,1000);

CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC(12,1); v_service NUMERIC(12,1);
BEGIN
 SELECT current_odometer,last_service_odometer INTO v_current,v_service
 FROM vehicles WHERE vehicle_id=p_vehicle_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle ID %',p_vehicle_id; END IF;
 RETURN v_current-v_service>=5000;
END; $$;

CREATE OR REPLACE FUNCTION fn_apply_trip_odometer()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC(12,1);
BEGIN
 SELECT current_odometer INTO v_current FROM vehicles
 WHERE vehicle_id=NEW.vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 IF NEW.start_odometer<>v_current THEN
  RAISE EXCEPTION 'Trip must start at current odometer (%)',v_current;
 END IF;
 IF NEW.end_odometer<=NEW.start_odometer THEN
  RAISE EXCEPTION 'End odometer must exceed start odometer';
 END IF;
 UPDATE vehicles SET current_odometer=NEW.end_odometer WHERE vehicle_id=NEW.vehicle_id;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_apply_trip_odometer BEFORE INSERT ON trips
FOR EACH ROW EXECUTE FUNCTION fn_apply_trip_odometer();

CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id BIGINT,p_trip_on DATE,p_start NUMERIC,p_end NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM vehicles WHERE vehicle_id=p_vehicle_id) THEN
  RAISE EXCEPTION 'Unknown vehicle ID %',p_vehicle_id;
 END IF;
 IF p_trip_on IS NULL OR p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN
  RAISE EXCEPTION 'Valid trip date and end odometer greater than start are required';
 END IF;
 INSERT INTO trips(vehicle_id,trip_on,start_odometer,end_odometer)
 VALUES(p_vehicle_id,p_trip_on,p_start,p_end);
END; $$;

-- Six trips are entered via the procedure after trigger installation.
CALL pr_record_trip(1,CURRENT_DATE-6,10000,10100);
CALL pr_record_trip(1,CURRENT_DATE-5,10100,10200);
CALL pr_record_trip(2,CURRENT_DATE-4,20000,20100);
CALL pr_record_trip(2,CURRENT_DATE-3,20100,20200);
CALL pr_record_trip(3,CURRENT_DATE-2,5000,5100);
CALL pr_record_trip(3,CURRENT_DATE-1,5100,5500);

CREATE OR REPLACE VIEW v_service_due AS
SELECT registration,current_odometer-last_service_odometer AS km_since_service
FROM vehicles WHERE current_odometer-last_service_odometer>=5000;

CREATE INDEX idx_trips_vehicle_trip_on ON trips(vehicle_id,trip_on);
EXPLAIN SELECT * FROM trips WHERE vehicle_id=1
 AND trip_on BETWEEN CURRENT_DATE-30 AND CURRENT_DATE;

CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO service_alerts(vehicle_id,km_since_service,flagged_on)
 SELECT vehicle_id,current_odometer-last_service_odometer,CURRENT_DATE
 FROM vehicles WHERE current_odometer-last_service_odometer>=5000
 ON CONFLICT(vehicle_id) DO UPDATE SET
 km_since_service=EXCLUDED.km_since_service,flagged_on=EXCLUDED.flagged_on;
 DELETE FROM service_alerts a USING vehicles v
 WHERE a.vehicle_id=v.vehicle_id
 AND v.current_odometer-v.last_service_odometer<5000;
END; $$;

SELECT * FROM vehicles;
SELECT * FROM v_service_due;
CALL pr_refresh_service_alerts();
SELECT * FROM service_alerts;
