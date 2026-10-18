-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL cleaning pipeline, step 1 of 5: load the six raw LTA CSV files into staging tables
--
-- Every field is loaded as text (VARCHAR 255), so no value is converted or cut before it is checked.
-- The header line is loaded as row 1, compared with the expected column order
-- (a stop check), and then deleted.
--
-- BEFORE RUNNING
--   1. Replace C:/Group20/raw_data/ with the folder that holds the raw files.
--      Use forward slashes on Windows.
--   2. Enable local file loading on both sides:
--        server: SET GLOBAL local_infile = 1;  (needs admin rights)
--        MySQL Workbench: Edit connection > Advanced > Others: OPT_LOCAL_INFILE=1
--   3. If a header check fails, open the CSV, read its first line and reorder
--      the @c variables in that LOAD DATA statement to match.
--   4. The files from data.gov.sg end lines with LF ('\n'). If a file was re-saved
--      in Excel (CRLF line endings), change LINES TERMINATED BY '\n' to '\r\n'
--      for that file; the line-break check below stops the run when this is needed.
-- =====================================================================

USE byd_bev_sg;

-- ---------------------------------------------------------------------
-- 1.1 M03 monthly new car registrations by make (core source)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_m03_raw;
CREATE TABLE stg_m03_raw (
    row_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    month          VARCHAR(255) NULL,
    make           VARCHAR(255) NULL,
    importer_type  VARCHAR(255) NULL,
    fuel_type      VARCHAR(255) NULL,
    vehicle_type   VARCHAR(255) NULL,
    number         VARCHAR(255) NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/M03-Car_Regn_by_make.csv'
INTO TABLE stg_m03_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4, @c5, @c6)
SET month         = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    make          = TRIM(@c2),
    importer_type = TRIM(@c3),
    fuel_type     = TRIM(@c4),
    vehicle_type  = TRIM(@c5),
    number        = TRIM(REPLACE(@c6, '\r', ''));

CALL etl_check('load', 'M03 header matches month,make,importer_type,fuel_type,vehicle_type,number',
    (SELECT COUNT(*) FROM stg_m03_raw
     WHERE row_id = 1 AND month = 'month' AND make = 'make' AND importer_type = 'importer_type'
       AND fuel_type = 'fuel_type' AND vehicle_type = 'vehicle_type' AND number = 'number'), 1);
DELETE FROM stg_m03_raw WHERE row_id = 1;
DELETE FROM stg_m03_raw WHERE CONCAT_WS('', month, make, importer_type, fuel_type, vehicle_type, number) = '';
CALL etl_check('load', 'M03 rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_m03_raw WHERE CONCAT_WS('|', month, make, importer_type, fuel_type, vehicle_type, number) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'M03 raw rows', (SELECT COUNT(*) FROM stg_m03_raw));

-- ---------------------------------------------------------------------
-- 1.2 COE bidding results
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_coe_raw;
CREATE TABLE stg_coe_raw (
    row_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    month          VARCHAR(255) NULL,
    bidding_no     VARCHAR(255) NULL,
    vehicle_class  VARCHAR(255) NULL,
    quota          VARCHAR(255) NULL,
    bids_success   VARCHAR(255) NULL,
    bids_received  VARCHAR(255) NULL,
    premium        VARCHAR(255) NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/COEBiddingResultsPrices.csv'
INTO TABLE stg_coe_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4, @c5, @c6, @c7)
SET month         = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    bidding_no    = TRIM(@c2),
    vehicle_class = TRIM(@c3),
    quota         = TRIM(@c4),
    bids_success  = TRIM(@c5),
    bids_received = TRIM(@c6),
    premium       = TRIM(REPLACE(@c7, '\r', ''));

CALL etl_check('load', 'COE header matches month,bidding_no,vehicle_class,quota,bids_success,bids_received,premium',
    (SELECT COUNT(*) FROM stg_coe_raw
     WHERE row_id = 1 AND month = 'month' AND bidding_no = 'bidding_no' AND vehicle_class = 'vehicle_class'
       AND quota = 'quota' AND bids_success = 'bids_success' AND bids_received = 'bids_received'
       AND premium = 'premium'), 1);
DELETE FROM stg_coe_raw WHERE row_id = 1;
DELETE FROM stg_coe_raw WHERE CONCAT_WS('', month, bidding_no, vehicle_class, quota, bids_success, bids_received, premium) = '';
CALL etl_check('load', 'COE rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_coe_raw WHERE CONCAT_WS('|', month, bidding_no, vehicle_class, quota, bids_success, bids_received, premium) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'COE raw rows', (SELECT COUNT(*) FROM stg_coe_raw));

-- ---------------------------------------------------------------------
-- 1.3 M09 vehicle population by fuel type
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_m09_raw;
CREATE TABLE stg_m09_raw (
    row_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    month     VARCHAR(255) NULL,
    category  VARCHAR(255) NULL,
    type      VARCHAR(255) NULL,
    number    VARCHAR(255) NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/M09-Vehs_by_Fuel_Type.csv'
INTO TABLE stg_m09_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4)
SET month    = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    category = TRIM(@c2),
    type     = TRIM(@c3),
    number   = TRIM(REPLACE(@c4, '\r', ''));

CALL etl_check('load', 'M09 header matches month,category,type,number',
    (SELECT COUNT(*) FROM stg_m09_raw
     WHERE row_id = 1 AND month = 'month' AND category = 'category' AND type = 'type' AND number = 'number'), 1);
DELETE FROM stg_m09_raw WHERE row_id = 1;
DELETE FROM stg_m09_raw WHERE CONCAT_WS('', month, category, type, number) = '';
CALL etl_check('load', 'M09 rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_m09_raw WHERE CONCAT_WS('|', month, category, type, number) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'M09 raw rows', (SELECT COUNT(*) FROM stg_m09_raw));

-- ---------------------------------------------------------------------
-- 1.4 MVP02 annual new car registrations by make and type
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_mvp02_raw;
CREATE TABLE stg_mvp02_raw (
    row_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    year           VARCHAR(255) NULL,
    make           VARCHAR(255) NULL,
    importer_type  VARCHAR(255) NULL,
    fuel           VARCHAR(255) NULL,
    type           VARCHAR(255) NULL,
    number         VARCHAR(255) NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/MVP02-2_New_Cars_by_make_type.csv'
INTO TABLE stg_mvp02_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4, @c5, @c6)
SET year          = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    make          = TRIM(@c2),
    importer_type = TRIM(@c3),
    fuel          = TRIM(@c4),
    type          = TRIM(@c5),
    number        = TRIM(REPLACE(@c6, '\r', ''));

CALL etl_check('load', 'MVP02 header matches year,make,importer_type,fuel,type,number',
    (SELECT COUNT(*) FROM stg_mvp02_raw
     WHERE row_id = 1 AND year = 'year' AND make = 'make' AND importer_type = 'importer_type'
       AND fuel = 'fuel' AND type = 'type' AND number = 'number'), 1);
DELETE FROM stg_mvp02_raw WHERE row_id = 1;
DELETE FROM stg_mvp02_raw WHERE CONCAT_WS('', year, make, importer_type, fuel, type, number) = '';
CALL etl_check('load', 'MVP02 rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_mvp02_raw WHERE CONCAT_WS('|', year, make, importer_type, fuel, type, number) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'MVP02 raw rows', (SELECT COUNT(*) FROM stg_mvp02_raw));

-- ---------------------------------------------------------------------
-- 1.5 MVP01 annual registrations by make (profiled only; excluded from analysis)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_mvp01_raw;
CREATE TABLE stg_mvp01_raw (
    row_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    year       VARCHAR(255) NULL,
    make       VARCHAR(255) NULL,
    fuel_type  VARCHAR(255) NULL,
    number     VARCHAR(255) NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/MVP01-6_Cars_by_make.csv'
INTO TABLE stg_mvp01_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4)
SET year      = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    make      = TRIM(@c2),
    fuel_type = TRIM(@c3),
    number    = TRIM(REPLACE(@c4, '\r', ''));

CALL etl_check('load', 'MVP01 header matches year,make,fuel_type,number',
    (SELECT COUNT(*) FROM stg_mvp01_raw
     WHERE row_id = 1 AND year = 'year' AND make = 'make' AND fuel_type = 'fuel_type' AND number = 'number'), 1);
DELETE FROM stg_mvp01_raw WHERE row_id = 1;
DELETE FROM stg_mvp01_raw WHERE CONCAT_WS('', year, make, fuel_type, number) = '';
CALL etl_check('load', 'MVP01 rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_mvp01_raw WHERE CONCAT_WS('|', year, make, fuel_type, number) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'MVP01 raw rows', (SELECT COUNT(*) FROM stg_mvp01_raw));

-- ---------------------------------------------------------------------
-- 1.6 EV charging point registry, June 2026 snapshot (source headers are renamed here)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_charger_raw;
CREATE TABLE stg_charger_raw (
    row_id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
    charger_code       VARCHAR(255) NULL COMMENT 'EV Charger Registration Code',
    operator_name      VARCHAR(255) NULL COMMENT 'operator',
    outlets            VARCHAR(255) NULL COMMENT 'No. of Charging Outlets',
    cp_id              VARCHAR(255) NULL COMMENT 'evCpId',
    plug_type          VARCHAR(255) NULL COMMENT 'plugType',
    charging_speed_kw  VARCHAR(255) NULL COMMENT 'charging Speed',
    postal_code        VARCHAR(255) NULL COMMENT 'PostalCode',
    block_no           VARCHAR(255) NULL COMMENT 'Block/House No',
    street_name        VARCHAR(255) NULL COMMENT 'Street Name',
    building_name      VARCHAR(255) NULL COMMENT 'Building Name',
    floor_no           VARCHAR(255) NULL COMMENT 'Floor No',
    lot_no             VARCHAR(255) NULL COMMENT 'Lot No',
    public_accessible  VARCHAR(255) NULL COMMENT 'Is the charger publicly accessible?',
    longitude          VARCHAR(255) NULL COMMENT 'longitude',
    latitude           VARCHAR(255) NULL COMMENT 'latitude',
    registration_date  VARCHAR(255) NULL COMMENT 'Registration Date',
    parking_lot_type   VARCHAR(255) NULL COMMENT 'Type of Parking Lot',
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOAD DATA LOCAL INFILE 'C:/Group20/raw_data/Electric_Vehicle_Charging_Points_Jun 2026.csv'
INTO TABLE stg_charger_raw CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
(@c1, @c2, @c3, @c4, @c5, @c6, @c7, @c8, @c9, @c10, @c11, @c12, @c13, @c14, @c15, @c16, @c17)
SET charger_code      = TRIM(REPLACE(@c1, CONVERT(UNHEX('EFBBBF') USING utf8mb4), '')),
    operator_name     = TRIM(@c2),
    outlets           = TRIM(@c3),
    cp_id             = TRIM(@c4),
    plug_type         = TRIM(@c5),
    charging_speed_kw = TRIM(@c6),
    postal_code       = TRIM(@c7),
    block_no          = TRIM(@c8),
    street_name       = TRIM(@c9),
    building_name     = TRIM(@c10),
    floor_no          = TRIM(@c11),
    lot_no            = TRIM(@c12),
    public_accessible = TRIM(@c13),
    longitude         = TRIM(@c14),
    latitude          = TRIM(@c15),
    registration_date = TRIM(@c16),
    parking_lot_type  = TRIM(REPLACE(@c17, '\r', ''));

CALL etl_check('load', 'Charger header matches the 17 expected source columns',
    (SELECT COUNT(*) FROM stg_charger_raw
     WHERE row_id = 1 AND charger_code = 'EV Charger Registration Code' AND operator_name = 'operator'
       AND outlets = 'No. of Charging Outlets' AND cp_id = 'evCpId' AND plug_type = 'plugType'
       AND charging_speed_kw = 'charging Speed' AND postal_code = 'PostalCode'
       AND block_no = 'Block/House No' AND street_name = 'Street Name' AND building_name = 'Building Name'
       AND floor_no = 'Floor No' AND lot_no = 'Lot No'
       AND public_accessible = 'Is the charger publicly accessible?'
       AND longitude = 'longitude' AND latitude = 'latitude'
       AND registration_date = 'Registration Date' AND parking_lot_type = 'Type of Parking Lot'), 1);
DELETE FROM stg_charger_raw WHERE row_id = 1;
DELETE FROM stg_charger_raw WHERE CONCAT_WS('', charger_code, cp_id, operator_name) = '';
CALL etl_check('load', 'Charger rows with a line break inside a field (wrong line ending setting)',
    (SELECT COUNT(*) FROM stg_charger_raw WHERE CONCAT_WS('|', charger_code, operator_name, outlets, cp_id, plug_type, charging_speed_kw, postal_code, block_no, street_name, building_name, floor_no, lot_no, public_accessible, longitude, latitude, registration_date, parking_lot_type) LIKE CONCAT('%', CHAR(10), '%')), 0);
CALL etl_info('load', 'Charger raw rows', (SELECT COUNT(*) FROM stg_charger_raw));
