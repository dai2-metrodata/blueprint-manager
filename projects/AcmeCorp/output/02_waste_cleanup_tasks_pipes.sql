-- =============================================================================
-- ACMECORP - WASTE CLEANUP: Unnecessary Tasks & Pipes
-- =============================================================================
-- Generated: 2026-04-02
-- Account:   cq29142
-- Purpose:   Suspend/remove tasks and pipes burning credits without value
-- =============================================================================
--
-- IMPACT SUMMARY:
--   Item 1: Samooha EXPECTED_VERSION_TASK  → 1,477 failures in 30 days
--   Item 2: Samooha PROCESS_ACTIVATIONS    → 57 skipped runs in 30 days
--   Item 3: Kafka Connector Pipe           → 1,573 polls, 0 files in 37 days
--   Item 4: SAP MARA_MERGE_T              → 57 skipped runs in 30 days
--
-- ⚠️  INSTRUCTIONS:
--   1. Review each section before executing
--   2. Run verification queries FIRST to confirm current state
--   3. Execute suspensions one at a time
--   4. Run post-action verification after each change
-- =============================================================================


-- #############################################################################
-- ITEM 1: SAMOOHA EXPECTED_VERSION_TASK (CRITICAL - 100% failure rate)
-- #############################################################################
-- Database:   SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.ADMIN
-- Runs:       1,477 in 30 days (~every 29 minutes)
-- Failures:   1,477 (100%)
-- Impact:     Unnecessary compute cycles, pollutes task history
-- Root Cause: Snowflake Data Clean Room app version check failing
-- =============================================================================

-- Step 1: Verify current state
SHOW TASKS LIKE 'EXPECTED_VERSION_TASK' IN SCHEMA SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.ADMIN;

-- Step 2: Confirm failure pattern
SELECT 
    state,
    COUNT(*) AS run_count,
    MIN(scheduled_time) AS first_run,
    MAX(scheduled_time) AS last_run
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE database_name = 'SAMOOHA_BY_SNOWFLAKE_LOCAL_DB'
  AND name = 'EXPECTED_VERSION_TASK'
  AND scheduled_time >= DATEADD('D', -7, CURRENT_DATE)
GROUP BY state;

-- Step 3: Suspend the task
-- ⚠️  This task belongs to a Snowflake Native App. You may need the app's
--     owner role. If the ALTER fails, try dropping the app instead (Item 1b).
ALTER TASK SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.ADMIN.EXPECTED_VERSION_TASK SUSPEND;

-- Step 4: Verify suspension
SHOW TASKS LIKE 'EXPECTED_VERSION_TASK' IN SCHEMA SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.ADMIN;
-- Expected: state = 'suspended'

-- Step 1b (ALTERNATIVE): If you are NOT using Snowflake Data Clean Rooms,
-- remove the entire app to eliminate all Samooha tasks at once:
--
-- DROP APPLICATION IF EXISTS SAMOOHA_BY_SNOWFLAKE_LOCAL_DB;
--
-- This also removes PROCESS_ACTIVATIONS and DELETE_OLD_ACTIVATION_DATA_TASK.


-- #############################################################################
-- ITEM 2: SAMOOHA PROCESS_ACTIVATIONS (100% skipped)
-- #############################################################################
-- Database:   SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.PROVIDER
-- Runs:       57 in 30 days
-- Skipped:    57 (100% - precondition never true)
-- Impact:     Low credit cost but unnecessary overhead
-- =============================================================================

-- Step 1: Verify current state
SHOW TASKS LIKE 'PROCESS_ACTIVATIONS' IN SCHEMA SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.PROVIDER;

-- Step 2: Suspend the task
ALTER TASK SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.PROVIDER.PROCESS_ACTIVATIONS SUSPEND;

-- Step 3: Verify suspension
SHOW TASKS LIKE 'PROCESS_ACTIVATIONS' IN SCHEMA SAMOOHA_BY_SNOWFLAKE_LOCAL_DB.PROVIDER;


-- #############################################################################
-- ITEM 3: KAFKA CONNECTOR PIPE (37 days, zero files ingested)
-- #############################################################################
-- Pipe:       MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2
--             .SNOWFLAKE_KAFKA_CONNECTOR_SNOWFLAKE_CONNECTOR_382808174_PIPE_STREAMING_0
-- Polls:      1,573 in 37 days
-- Files:      0
-- Bytes:      0
-- Credits:    0.00 (but consuming cloud services overhead)
-- Root Cause: Kafka connector configured but no data flowing from MSK
-- =============================================================================

-- Step 1: Check current pipe status
SELECT SYSTEM$PIPE_STATUS(
  'MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2.SNOWFLAKE_KAFKA_CONNECTOR_SNOWFLAKE_CONNECTOR_382808174_PIPE_STREAMING_0'
);

-- Step 2: Pause the pipe
ALTER PIPE MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2.SNOWFLAKE_KAFKA_CONNECTOR_SNOWFLAKE_CONNECTOR_382808174_PIPE_STREAMING_0
  SET PIPE_EXECUTION_PAUSED = TRUE;

-- Step 3: Verify pipe is paused
SELECT SYSTEM$PIPE_STATUS(
  'MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2.SNOWFLAKE_KAFKA_CONNECTOR_SNOWFLAKE_CONNECTOR_382808174_PIPE_STREAMING_0'
);
-- Expected: executionState = PAUSED

-- Step 4 (OPTIONAL): If the Kafka connector is fully decommissioned:
-- DROP PIPE IF EXISTS MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2.SNOWFLAKE_KAFKA_CONNECTOR_SNOWFLAKE_CONNECTOR_382808174_PIPE_STREAMING_0;

-- Step 5 (OPTIONAL): If the entire MSK streaming setup is unused:
-- DROP SCHEMA IF EXISTS MSK_STREAMING_DB.MSK_STREAMING_SCHEMA2;
-- DROP DATABASE IF EXISTS MSK_STREAMING_DB;


-- #############################################################################
-- ITEM 4: SAP MARA MERGE TASK (100% skipped - investigate)
-- #############################################################################
-- Database:   SAP.RAW
-- Task:       ZGT_SNOWFLAKE_MARA_MERGE_T
-- Runs:       57 in 30 days
-- Skipped:    57 (100% - precondition never met)
-- Note:       CONTROLLER and CONTROL_MERGE run fine (738 runs each)
--             This suggests the SAP extraction for MARA table is not active
-- =============================================================================

-- Step 1: Check the task definition and its WHEN condition
SHOW TASKS LIKE 'ZGT_SNOWFLAKE_MARA_MERGE_T' IN SCHEMA SAP.RAW;

-- Step 2: Check if the upstream stream has data
-- (The WHEN condition likely checks a stream; identify it from the task definition)

-- Step 3: Decision tree:
--   IF MARA extraction is expected to be active:
--     → Investigate the SAP Glue connector configuration
--     → Check SNP_GLUE_CONNECTOR_FOR_SAP app health
--
--   IF MARA extraction is intentionally disabled:
--     → Suspend the task to stop unnecessary evaluations:
-- ALTER TASK SAP.RAW.ZGT_SNOWFLAKE_MARA_MERGE_T SUSPEND;


-- #############################################################################
-- POST-CLEANUP VERIFICATION
-- #############################################################################
-- Run this 24 hours after applying changes to confirm waste is eliminated

-- Check: No new failures from suspended tasks
SELECT 
    database_name,
    name AS task_name,
    state,
    COUNT(*) AS runs
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE scheduled_time >= DATEADD('H', -24, CURRENT_TIMESTAMP())
  AND name IN (
    'EXPECTED_VERSION_TASK',
    'PROCESS_ACTIVATIONS',
    'ZGT_SNOWFLAKE_MARA_MERGE_T'
  )
GROUP BY database_name, name, state
ORDER BY database_name, name;
-- Expected: 0 rows (tasks should no longer be running)

-- Check: Pipe polling has stopped
SELECT 
    pipe_name,
    COUNT(*) AS polls,
    SUM(files_inserted) AS files
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time >= DATEADD('H', -24, CURRENT_TIMESTAMP())
GROUP BY pipe_name;
-- Expected: No rows for the Kafka pipe

-- Check: Serverless credit consumption trending down
SELECT 
    DATE_TRUNC('day', start_time) AS day,
    ROUND(SUM(credits_used), 4) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
WHERE start_time >= DATEADD('D', -7, CURRENT_DATE)
GROUP BY DATE_TRUNC('day', start_time)
ORDER BY day DESC;
