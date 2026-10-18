-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL cleaning pipeline, step 0 of 4: database, check log and stop-check procedures
--
-- Run order: 00_setup.sql -> 01_load_raw.sql -> 02_clean.sql
--            -> 03_build_star_schema.sql -> 04_validate.sql
-- Target: MySQL 8.0 (also tested on MariaDB 10.11)
-- Every check writes one row to etl_check_log. A failed stop check raises
-- SQLSTATE 45000, which halts the script in MySQL Workbench and the mysql client.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS byd_bev_sg CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE byd_bev_sg;

DROP TABLE IF EXISTS etl_check_log;
CREATE TABLE etl_check_log (
    check_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    stage           VARCHAR(20)   NOT NULL COMMENT 'load / clean / build / validate',
    check_name      VARCHAR(200)  NOT NULL,
    actual_value    VARCHAR(100)  NULL,
    expected_value  VARCHAR(100)  NULL,
    status          VARCHAR(4)    NOT NULL COMMENT 'PASS / FAIL / INFO',
    checked_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (check_id)
) ENGINE=InnoDB COMMENT='One row per pipeline check';

DROP PROCEDURE IF EXISTS etl_check;
DROP PROCEDURE IF EXISTS etl_info;

DELIMITER $$

-- Stop check: logs the result and halts the run when actual <> expected
CREATE PROCEDURE etl_check(IN p_stage VARCHAR(20), IN p_name VARCHAR(200),
                           IN p_actual BIGINT, IN p_expected BIGINT)
BEGIN
    DECLARE v_status VARCHAR(4);
    DECLARE v_msg    VARCHAR(255);
    SET v_status = IF(p_actual = p_expected, 'PASS', 'FAIL');
    INSERT INTO etl_check_log (stage, check_name, actual_value, expected_value, status)
    VALUES (p_stage, p_name, IFNULL(p_actual, 'NULL'), p_expected, v_status);
    IF v_status = 'FAIL' THEN
        SET v_msg = LEFT(CONCAT('STOP CHECK FAILED: ', p_name, ' | actual ',
                                IFNULL(p_actual, 'NULL'), ', expected ', p_expected), 255);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END$$

-- Information only: records a count or range without stopping the run
CREATE PROCEDURE etl_info(IN p_stage VARCHAR(20), IN p_name VARCHAR(200), IN p_value VARCHAR(100))
BEGIN
    INSERT INTO etl_check_log (stage, check_name, actual_value, status)
    VALUES (p_stage, p_name, p_value, 'INFO');
END$$

DELIMITER ;
