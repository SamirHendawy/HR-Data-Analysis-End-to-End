-- ------------------------------------
-- Data Cleaning Using SQL
-- ------------------------------------
-- ------------------------------------
-- Phase 1: Setup & Initial Inspection
-- ------------------------------------
-- ------------------------------------
-- 1.1 Create and Use Database
CREATE DATABASE IF NOT EXISTS hrData;
USE hrData;
-- ------------------------------------
-- 1.2 Inspect Raw Data
SELECT * FROM humanresources LIMIT 10;
-- ------------------------------------
-- 1.3 Fix ID Column Name 
ALTER TABLE humanresources
CHANGE COLUMN ï»¿id employee_id VARCHAR(25) NULL;
-- ------------------------------------
-- 1.4 Check for Duplicates in Primary Key
SELECT employee_id, COUNT(*) 
FROM humanresources 
GROUP BY employee_id 
HAVING COUNT(*) > 1;
-- No Duplicated ..
-- ------------------------------------
-- 1.5 Describe Table Structure
DESCRIBE humanresources;
-- ------------------------------------
-- ------------------------------------
-- Phase 2: Date Standardization
-- ------------------------------------
-- ------------------------------------
SET sql_safe_updates = 0; -- Authentication for update

-- 2.1 Handle Birthdate "%Y-%m-%d"
UPDATE humanresources 
SET birthdate = CASE
    WHEN birthdate LIKE "%/%" THEN DATE_FORMAT(STR_TO_DATE(birthdate, "%m/%d/%Y"), "%Y-%m-%d")
    WHEN birthdate LIKE "%-%" THEN DATE_FORMAT(STR_TO_DATE(birthdate, "%m-%d-%Y"), "%Y-%m-%d")
    ELSE NULL
END;

ALTER TABLE humanresources MODIFY COLUMN birthdate DATE;
-- ------------------------------------
-- 2.2 Handle Hire Date "%Y-%m-%d" (with Deep Clean)
UPDATE humanresources 
SET hire_date = CASE
    WHEN hire_date LIKE "%/%" THEN DATE_FORMAT(STR_TO_DATE(REPLACE(REPLACE(TRIM(hire_date), "\r", ""), "\n", ""), "%m/%d/%Y"), "%Y-%m-%d")
    WHEN hire_date LIKE "%-%" THEN DATE_FORMAT(STR_TO_DATE(REPLACE(REPLACE(TRIM(hire_date), "\r", ""), "\n", ""), "%m-%d-%Y"), "%Y-%m-%d")
    ELSE NULL
END;

ALTER TABLE humanresources MODIFY COLUMN hire_date DATE;
-- ------------------------------------
-- ------------------------------------
-- Phase 3: Handling Terminations & NULLs
-- ------------------------------------
-- ------------------------------------
-- Use Savepoint for safe parsing
SAVEPOINT a;

-- 3.1 Parse UTC DateTime to standard Date
UPDATE humanresources 
SET termdate = DATE(STR_TO_DATE(termdate, '%Y-%m-%d %H:%i:%s UTC'))
WHERE termdate IS NOT NULL 
  AND termdate != '' 
  AND termdate != ' '
  AND termdate != '0000-00-00';
-- ------------------------------------
-- 3.2 Standardize Empty Strings to True NULLs
UPDATE humanresources
SET termdate = NULL
WHERE termdate = '' OR termdate = ' ' OR termdate = '0000-00-00';

RELEASE SAVEPOINT a;

ALTER TABLE humanresources MODIFY COLUMN termdate DATE;

-- ------------------------------------
-- ------------------------------------
-- Phase 4: Feature Engineering
-- ------------------------------------
-- ------------------------------------
-- 4.1 Fix the Root Cause of the Age Issue (The Century Bug)
-- Shift anomalous future birthdates back to the 20th century
UPDATE humanresources 
SET birthdate = DATE_SUB(birthdate, INTERVAL 100 YEAR) 
WHERE birthdate > CURDATE();

-- 4.2 Add and Calculate Age (Clean calculation after fixing the root data)
ALTER TABLE humanresources ADD COLUMN age INT;

UPDATE humanresources
SET age = timestampdiff(YEAR, birthdate, CURDATE());

-- 4.3 Flag Future Terminations (Notice Period / Contracts ending)
ALTER TABLE humanresources ADD COLUMN future_term TINYINT(1) DEFAULT 0; 

UPDATE humanresources 
SET future_term = 1 
WHERE termdate > CURDATE();

-- 4.4 Calculate Employee Tenure 

ALTER TABLE humanresources ADD COLUMN tenure INT;
UPDATE humanresources 
SET tenure = CASE
	WHEN termdate IS NOT NULL AND termdate <= CURDATE() THEN TIMESTAMPDIFF(YEAR, hire_date, termdate)
    ELSE TIMESTAMPDIFF(YEAR, hire_date, termdate)
END;

-- 4.5 Active Employee Vs. Terminated..

ALTER TABLE humanresources ADD COLUMN employment_status VARCHAR(20);
UPDATE humanresources
SET employment_status = CASE
    WHEN termdate IS NULL OR termdate > CURDATE() THEN 'Active'
    ELSE 'Terminated'
END;


-- ------------------------------------
-- ------------------------------------
-- Phase 5: Data Validation & QA
-- ------------------------------------
-- ------------------------------------
-- 5.1 Check Age Range (Should be logical now, no 5-year-olds)
SELECT
    MIN(age) AS min_age, 
    MAX(age) AS max_age, 
    ROUND(AVG(age)) AS avg_age
FROM humanresources;
    
-- 5.2 Check Underage Employees (Should be 0 if the fix worked perfectly)
SELECT COUNT(*) AS Underage_Count FROM humanresources WHERE age < 18; -- 0

-- 5.3 Validate Future Terms
SELECT COUNT(*) AS Future_Term_Count FROM humanresources WHERE termdate > CURDATE(); -- 1085 EMPLOYEES

-- 5.4 Check Location Diversity
SELECT COUNT(DISTINCT location) AS Distinct_Locations FROM humanresources; -- 

-- Re-enable Safe Updates
SET sql_safe_updates = 1;
-- ------------------------------------
-- Cleaning Is Done ... -_-
-- ------------------------------------