-- =============================================================================
-- ACMECORP - WAREHOUSE RIGHT-SIZING & CLEANUP
-- =============================================================================
-- Generated: 2026-04-02
-- Account:   cq29142
-- Purpose:   Downsize over-provisioned warehouses and drop unused ones
-- =============================================================================
--
-- IMPACT SUMMARY:
--   Downsizes:  2 warehouses (Medium → X-Small)
--   Drops:      3 warehouses (X-Large, Medium, Medium)
--   Exposure eliminated: 28 credits/hour if accidentally resumed
--
-- ⚠️  INSTRUCTIONS:
--   1. Run pre-action verification for each item
--   2. Execute changes one at a time
--   3. Run post-action verification after each change
--   4. Monitor for 24-48 hours before proceeding to next item
-- =============================================================================

USE ROLE ACCOUNTADMIN;


-- #############################################################################
-- ITEM 1: DOWNSIZE AI_ML_WAREHOUSE (Medium → X-Small)
-- #############################################################################
-- Current:    Medium (4 credits/hr)
-- Recommend:  X-Small (1 credit/hr)
-- Evidence:   56 queries in 30 days, avg 0.35s, max 0.65s, zero data scanned
-- Savings:    75% credit reduction when running
-- =============================================================================

-- Step 1: Verify current config and state
SHOW WAREHOUSES LIKE 'AI_ML_WAREHOUSE';

-- Step 2: Verify no active sessions
SELECT 
    warehouse_name,
    COUNT(*) AS active_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'AI_ML_WAREHOUSE'
  AND start_time >= DATEADD('H', -1, CURRENT_TIMESTAMP())
  AND execution_status = 'RUNNING'
GROUP BY warehouse_name;

-- Step 3: Downsize
ALTER WAREHOUSE AI_ML_WAREHOUSE SET WAREHOUSE_SIZE = 'X-SMALL';

-- Step 4: Verify new size
SHOW WAREHOUSES LIKE 'AI_ML_WAREHOUSE';
-- Expected: size = X-Small

-- Step 5 (OPTIONAL): If no workload materializes after 30 days, drop it:
-- DROP WAREHOUSE IF EXISTS AI_ML_WAREHOUSE;


-- #############################################################################
-- ITEM 2: DOWNSIZE ETL_WH (Medium → X-Small)
-- #############################################################################
-- Current:    Medium (4 credits/hr)
-- Recommend:  X-Small (1 credit/hr)
-- Evidence:   14 queries in 30 days (1 active day), avg 0.42s, max 2.1s,
--             zero data scanned, no spilling, no queuing
-- Savings:    75% credit reduction when running
-- =============================================================================

-- Step 1: Verify current config
SHOW WAREHOUSES LIKE 'ETL_WH';

-- Step 2: Verify no recent workload that might need Medium
SELECT 
    DATE_TRUNC('day', start_time) AS day,
    COUNT(*) AS queries,
    ROUND(MAX(total_elapsed_time) / 1000, 2) AS max_elapsed_sec,
    ROUND(MAX(bytes_scanned) / POWER(1024, 3), 4) AS max_gb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'ETL_WH'
  AND start_time >= DATEADD('D', -30, CURRENT_DATE)
  AND execution_status = 'SUCCESS'
GROUP BY DATE_TRUNC('day', start_time)
ORDER BY day DESC;

-- Step 3: Downsize
ALTER WAREHOUSE ETL_WH SET WAREHOUSE_SIZE = 'X-SMALL';

-- Step 4: Verify
SHOW WAREHOUSES LIKE 'ETL_WH';
-- Expected: size = X-Small

-- NOTE: If ETL workloads increase in the future, you can resize back:
-- ALTER WAREHOUSE ETL_WH SET WAREHOUSE_SIZE = 'MEDIUM';


-- #############################################################################
-- ITEM 3: DROP DCR_ACTIVATION_WAREHOUSE (X-Large, idle 7+ months)
-- #############################################################################
-- Current:    X-Large (16 credits/hr) ⚠️ HIGHEST RISK
-- Last used:  September 2025
-- Owner:      SAMOOHA_APP_ROLE
-- Evidence:   Zero queries in 90+ days
-- Risk:       If accidentally resumed, burns 16 credits/hour
-- =============================================================================

-- Step 1: Confirm zero recent activity
SELECT COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'DCR_ACTIVATION_WAREHOUSE'
  AND start_time >= DATEADD('D', -90, CURRENT_DATE);
-- Expected: 0

-- Step 2: Confirm no dependent objects
SELECT 
    object_type,
    object_name,
    object_database,
    object_schema
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE referenced_object_name = 'DCR_ACTIVATION_WAREHOUSE'
  AND referenced_object_domain = 'WAREHOUSE';
-- Expected: 0 rows (or only Samooha objects being removed)

-- Step 3: Drop the warehouse
DROP WAREHOUSE IF EXISTS DCR_ACTIVATION_WAREHOUSE;

-- Step 4: Verify
SHOW WAREHOUSES LIKE 'DCR_ACTIVATION_WAREHOUSE';
-- Expected: 0 rows


-- #############################################################################
-- ITEM 4: DROP ML_PROD_WH (Medium, idle 10+ months)
-- #############################################################################
-- Current:    Medium (4 credits/hr)
-- Last used:  June 2025
-- Evidence:   Zero queries in 90+ days, never used for production ML
-- =============================================================================

-- Step 1: Confirm zero recent activity
SELECT COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'ML_PROD_WH'
  AND start_time >= DATEADD('D', -90, CURRENT_DATE);
-- Expected: 0

-- Step 2: Drop
DROP WAREHOUSE IF EXISTS ML_PROD_WH;

-- Step 3: Verify
SHOW WAREHOUSES LIKE 'ML_PROD_WH';
-- Expected: 0 rows


-- #############################################################################
-- ITEM 5: DROP MLOPS_WH (Medium, idle 10+ months)
-- #############################################################################
-- Current:    Medium (4 credits/hr)
-- Last used:  June 2025
-- Evidence:   Zero queries in 90+ days, provisioned but never adopted
-- =============================================================================

-- Step 1: Confirm zero recent activity
SELECT COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'MLOPS_WH'
  AND start_time >= DATEADD('D', -90, CURRENT_DATE);
-- Expected: 0

-- Step 2: Drop
DROP WAREHOUSE IF EXISTS MLOPS_WH;

-- Step 3: Verify
SHOW WAREHOUSES LIKE 'MLOPS_WH';
-- Expected: 0 rows


-- #############################################################################
-- BONUS: DROP REMAINING IDLE WAREHOUSES (all zero usage for 90+ days)
-- #############################################################################
-- These are all X-Small or Small (low risk), but add clutter and surface area.
-- Review each and uncomment to drop if confirmed unused.
-- =============================================================================

-- Quickstart / lab warehouses (created Oct 2024, never used since)
-- DROP WAREHOUSE IF EXISTS QUICKSTART_WH;
-- DROP WAREHOUSE IF EXISTS QUICKSTART_VCK;
-- DROP WAREHOUSE IF EXISTS QUICKSTART_PETER_WH;
-- DROP WAREHOUSE IF EXISTS QUICKSTART_WH_HR;
-- DROP WAREHOUSE IF EXISTS QUICKSTART_WH_ALDO;
-- DROP WAREHOUSE IF EXISTS QUICKSTART_W_WH;

-- Tasty Bytes demo warehouses (last used Aug 2024)
-- DROP WAREHOUSE IF EXISTS TB_DEV_WH;
-- DROP WAREHOUSE IF EXISTS TB_DE_WH;

-- Provisioning template warehouses (never used)
-- DROP WAREHOUSE IF EXISTS DASHBOARD_WH;
-- DROP WAREHOUSE IF EXISTS METADATA_WH;       -- Size: Small
-- DROP WAREHOUSE IF EXISTS MONITORING_WH;

-- Feature-specific warehouses (abandoned)
-- DROP WAREHOUSE IF EXISTS DATA_CLEAN_ROOM;
-- DROP WAREHOUSE IF EXISTS MSK_STREAMING_WH;  -- Size: Small (related to idle Kafka pipe)
-- DROP WAREHOUSE IF EXISTS NOTEBOOK_WAREHOUSE;
-- DROP WAREHOUSE IF EXISTS POWERBI;
-- DROP WAREHOUSE IF EXISTS ML_DEV_WH;
-- DROP WAREHOUSE IF EXISTS DEMO_WH;
-- DROP WAREHOUSE IF EXISTS HOL_ICE_WH;


-- #############################################################################
-- POST-REMEDIATION VALIDATION
-- #############################################################################

-- Check 1: Verify downsized warehouses
SELECT name, size, auto_suspend, state
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)))
WHERE name IN ('AI_ML_WAREHOUSE', 'ETL_WH');

-- Check 2: List all remaining warehouses with sizes
SHOW WAREHOUSES;

-- Check 3: Count warehouses by size (should have fewer Medium/Large)
SELECT 
    size,
    COUNT(*) AS warehouse_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP BY size
ORDER BY 
    CASE size
        WHEN 'X-Small' THEN 1
        WHEN 'Small' THEN 2
        WHEN 'Medium' THEN 3
        WHEN 'Large' THEN 4
        WHEN 'X-Large' THEN 5
        ELSE 6
    END;

-- Check 4: Monitor credit usage over next 7 days
-- Run this daily to confirm savings:
SELECT 
    warehouse_name,
    warehouse_size,
    DATE_TRUNC('day', start_time) AS day,
    ROUND(SUM(credits_used), 4) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('D', -7, CURRENT_DATE)
  AND warehouse_name IN ('AI_ML_WAREHOUSE', 'ETL_WH')
GROUP BY warehouse_name, warehouse_size, DATE_TRUNC('day', start_time)
ORDER BY day DESC, warehouse_name;


-- #############################################################################
-- SUMMARY
-- #############################################################################
/*
=============================================================================
ACTION                  WAREHOUSE                  BEFORE      AFTER
=============================================================================
DOWNSIZE                AI_ML_WAREHOUSE            Medium      X-Small
DOWNSIZE                ETL_WH                     Medium      X-Small
DROP                    DCR_ACTIVATION_WAREHOUSE   X-Large     REMOVED
DROP                    ML_PROD_WH                 Medium      REMOVED
DROP                    MLOPS_WH                   Medium      REMOVED
=============================================================================

EXPOSURE ELIMINATED:
  DCR_ACTIVATION_WAREHOUSE:  16 cr/hr
  ML_PROD_WH:                4 cr/hr
  MLOPS_WH:                  4 cr/hr
  AI_ML_WAREHOUSE savings:   3 cr/hr (4 → 1)
  ETL_WH savings:            3 cr/hr (4 → 1)
  ─────────────────────────────────────
  TOTAL:                     30 cr/hr exposure eliminated

  If all 5 warehouses ran for 1 hour accidentally:
    Before: 32 credits ($96 at $3/credit)
    After:  2 credits ($6 at $3/credit)

BONUS CLEANUP (optional):
  Up to 19 additional idle X-Small/Small warehouses available to drop.
  Reduces account clutter and security surface area.
=============================================================================
*/
