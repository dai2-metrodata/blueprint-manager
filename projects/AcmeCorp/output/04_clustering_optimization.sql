-- =============================================================================
-- ACMECORP - CLUSTERING KEY OPTIMIZATION
-- =============================================================================
-- Generated: 2026-04-02
-- Account:   cq29142
-- Purpose:   Add clustering keys to tables based on actual query access patterns
-- =============================================================================
--
-- FINDINGS SUMMARY:
--   1 table with severe clustering depth needs a clustering key
--   2 Snowflake billing view optimization opportunities (query rewrites)
--   2 existing SAP tables already well-clustered (no action)
--
-- ⚠️  IMPORTANT: Automatic reclustering consumes serverless credits.
--    Monitor AUTOMATIC_CLUSTERING_HISTORY after enabling.
-- =============================================================================

USE ROLE ACCOUNTADMIN;


-- #############################################################################
-- ITEM 1: ORDER_HEADER — ADD CLUSTERING KEY (HIGH IMPACT)
-- #############################################################################
-- Table:     SANDBOX_HANS.DBT_TEST_RAW.ORDER_HEADER
-- Size:      1.91 GB | 248,201,269 rows | 123 partitions
-- Problem:   Average depth 90.8 (extremely poor — all 123 partitions overlap)
--            100% full scan on filtered queries, taking 30 seconds
-- Queries:   Filter by year from ORDER_TS, join on CUSTOMER_ID, LOCATION_ID
-- Column:    ORDER_TS is TIMESTAMP_NTZ(9)
-- =============================================================================

-- Step 1: Verify current state (before)
-- Depth of 90.8 means almost every partition must be scanned for any filter
SELECT SYSTEM$CLUSTERING_INFORMATION(
  'SANDBOX_HANS.DBT_TEST_RAW.ORDER_HEADER', 
  '(TO_DATE(ORDER_TS))'
);
-- Expected: average_depth ≈ 90.8 (very bad — should be close to 1.0)

-- Step 2: Check current table size and partitions
SELECT 
    table_name,
    row_count,
    ROUND(bytes / POWER(1024, 3), 4) AS size_gb,
    clustering_key
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE table_catalog = 'SANDBOX_HANS'
  AND table_schema = 'DBT_TEST_RAW'
  AND table_name = 'ORDER_HEADER'
  AND deleted IS NULL;

-- Step 3: Add clustering key
-- Using TO_DATE(ORDER_TS) to reduce cardinality from timestamp to date.
-- This aligns with query patterns that filter by year/date range.
ALTER TABLE SANDBOX_HANS.DBT_TEST_RAW.ORDER_HEADER
  CLUSTER BY (TO_DATE(ORDER_TS));

-- Step 4: Verify clustering key was set
SHOW TABLES LIKE 'ORDER_HEADER' IN SCHEMA SANDBOX_HANS.DBT_TEST_RAW;

-- Step 5: Force initial reclustering (optional — system does this automatically)
-- The automatic reclustering service will begin reclustering in the background.
-- For a 1.91 GB table, this should complete within 30-60 minutes.

-- Step 6: Monitor reclustering progress
-- Run this periodically until average_depth approaches 1.0-2.0:
SELECT SYSTEM$CLUSTERING_INFORMATION('SANDBOX_HANS.DBT_TEST_RAW.ORDER_HEADER');

-- Step 7: Check reclustering credit cost
SELECT 
    table_name,
    ROUND(SUM(credits_used), 4) AS reclustering_credits,
    SUM(num_bytes_reclustered) AS bytes_reclustered,
    SUM(num_rows_reclustered) AS rows_reclustered
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE table_name = 'ORDER_HEADER'
  AND start_time >= CURRENT_DATE()
GROUP BY table_name;

/*
EXPECTED RESULTS AFTER RECLUSTERING:
  - average_depth: 90.8 → ~1.5-2.0
  - average_overlaps: 110.3 → ~1.0-3.0
  - Query scan %: 100% → ~25-30% (filtering 2 of ~4+ years)
  - Query time: ~30s → ~8-10s
  - Reclustering cost: ~0.5-2 credits (one-time for 1.91 GB)
*/


-- #############################################################################
-- ITEM 2: QUERY REWRITE — PARTNER_REMAINING_BALANCE_DAILY (93 GB scanned/mo)
-- #############################################################################
-- This is a Snowflake-managed table — CANNOT add clustering keys.
-- However, queries are scanning 88-97% of all partitions unnecessarily.
--
-- Problem: Queries use `SELECT *` or aggregate without date filters:
--   SELECT * FROM SNOWFLAKE.BILLING.PARTNER_REMAINING_BALANCE_DAILY
--   ^^^ scans 8.4 GB per execution (535 of 558 partitions)
--
-- Solution: Materialize a filtered subset OR add date predicates.
-- =============================================================================

-- Option A: Create a materialized view with recent data only
CREATE OR REPLACE TABLE PARTNER.BILLING.PARTNER_BALANCE_RECENT AS
SELECT *
FROM SNOWFLAKE.BILLING.PARTNER_REMAINING_BALANCE_DAILY
WHERE DATE >= DATEADD('month', -6, CURRENT_DATE());

-- Cluster the materialized copy
ALTER TABLE PARTNER.BILLING.PARTNER_BALANCE_RECENT
  CLUSTER BY (DATE, SOLD_TO_CUSTOMER_NAME);

-- Set up a daily refresh task (serverless)
CREATE OR REPLACE TASK PARTNER.BILLING.REFRESH_PARTNER_BALANCE
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
  COMMENT = 'Daily refresh of partner balance materialized table'
AS
  CREATE OR REPLACE TABLE PARTNER.BILLING.PARTNER_BALANCE_RECENT AS
  SELECT *
  FROM SNOWFLAKE.BILLING.PARTNER_REMAINING_BALANCE_DAILY
  WHERE DATE >= DATEADD('month', -6, CURRENT_DATE());

-- NOTE: Only enable this task if you decide to use the materialized approach:
-- ALTER TASK PARTNER.BILLING.REFRESH_PARTNER_BALANCE RESUME;

-- Option B: Rewrite existing queries with date filters (no new objects)
-- BEFORE (scans 8.4 GB):
--   SELECT * FROM SNOWFLAKE.BILLING.PARTNER_REMAINING_BALANCE_DAILY
--
-- AFTER (scans ~1-2 GB):
--   SELECT * FROM SNOWFLAKE.BILLING.PARTNER_REMAINING_BALANCE_DAILY
--   WHERE DATE >= DATEADD('month', -3, CURRENT_DATE())


-- #############################################################################
-- ITEM 3: QUERY REWRITE — WAREHOUSE_METERING_HISTORY (43 GB scanned/mo)
-- #############################################################################
-- Also Snowflake-managed — CANNOT add clustering keys.
-- Queries scan 46% of partitions on average.
-- =============================================================================

-- Recommendation: Always add time bounds to metering queries.
-- BEFORE (scans ~6.7 GB):
--   SELECT date_trunc('day', start_time) AS day,
--     account_name, SUM(credits_used) AS credits
--   FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
--   GROUP BY 1, 2
--
-- AFTER (scans ~0.5-1 GB):
--   SELECT date_trunc('day', start_time) AS day,
--     account_name, SUM(credits_used) AS credits
--   FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
--   WHERE start_time >= DATEADD('day', -30, CURRENT_DATE())
--   GROUP BY 1, 2


-- #############################################################################
-- EXISTING CLUSTERING — NO ACTION NEEDED
-- #############################################################################
-- These tables are already well-clustered:
--
-- +--------------------------------------------+-----------------------+---------+
-- | Table                                      | Clustering Key        | Depth   |
-- +--------------------------------------------+-----------------------+---------+
-- | DWH.DS.RAW_0FI_GL_10 (52 MB, 4.5M rows)   | LINEAR(GLREQUEST)     | 2.0     |
-- | DWH.DL.DL_SAP_GL_TRANSACTION_FIGURES       | LINEAR(GLREQUEST)     | Good    |
-- +--------------------------------------------+-----------------------+---------+
--
-- average_depth of 2.0 with 4 partitions is well-clustered.
-- Overlaps = 1.5 — minimal. No changes needed.


-- #############################################################################
-- MONITORING: POST-IMPLEMENTATION
-- #############################################################################

-- Run daily for the first week after adding clustering to ORDER_HEADER:

-- Check 1: Clustering depth improving
SELECT SYSTEM$CLUSTERING_INFORMATION('SANDBOX_HANS.DBT_TEST_RAW.ORDER_HEADER');
-- Target: average_depth < 3.0, average_overlaps < 5.0

-- Check 2: Reclustering credit spend
SELECT 
    DATE_TRUNC('day', start_time) AS day,
    table_name,
    ROUND(SUM(credits_used), 4) AS credits,
    SUM(num_bytes_reclustered) AS bytes_reclustered
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE start_time >= CURRENT_DATE() - 7
GROUP BY DATE_TRUNC('day', start_time), table_name
ORDER BY day DESC;

-- Check 3: Query performance improvement (after reclustering completes)
SELECT 
    LEFT(query_text, 150) AS query,
    partitions_scanned,
    partitions_total,
    ROUND(partitions_scanned * 100.0 / NULLIF(partitions_total, 0), 1) AS scan_pct,
    ROUND(bytes_scanned / POWER(1024, 2), 1) AS mb_scanned,
    ROUND(total_elapsed_time / 1000, 2) AS elapsed_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE UPPER(query_text) LIKE '%ORDER_HEADER%'
  AND start_time >= CURRENT_DATE() - 7
  AND execution_status = 'SUCCESS'
  AND partitions_total > 10
  AND query_type = 'SELECT'
ORDER BY start_time DESC
LIMIT 10;
-- Target: scan_pct < 40% (down from 100%), elapsed_sec < 10s (down from 30s)


-- #############################################################################
-- SUMMARY
-- #############################################################################
/*
=============================================================================
ACTION ITEMS
=============================================================================
#  | Table                        | Action              | Expected Impact
---|------------------------------|----------------------|-------------------
1  | ORDER_HEADER (1.91 GB)       | CLUSTER BY DATE      | 70% scan reduction
   |                              |                      | 30s → ~8-10s queries
   |                              |                      | ~0.5-2 cr one-time
---|------------------------------|----------------------|-------------------
2  | PARTNER_REMAINING_BALANCE    | Materialize subset   | 8.4 GB → ~1-2 GB
   | (Snowflake-managed)          | OR add date filters  | per query
---|------------------------------|----------------------|-------------------
3  | WAREHOUSE_METERING_HISTORY   | Add WHERE date >=    | 6.7 GB → ~0.5-1 GB
   | (Snowflake-managed)          | predicates           | per query
---|------------------------------|----------------------|-------------------
-- | DWH.DS.RAW_0FI_GL_10        | No action            | Already depth=2.0
-- | DWH.DL.DL_SAP_GL_TRANS...   | No action            | Already clustered
=============================================================================

ESTIMATED MONTHLY SCAN REDUCTION:
  ORDER_HEADER:        ~0.7 GB/mo saved (small table, few queries)
  PARTNER_BALANCE:     ~65 GB/mo saved (34 queries × ~1.9 GB reduction each)
  METERING_HISTORY:    ~32 GB/mo saved (33 queries × ~1.0 GB reduction each)
  ────────────────────────────────────────────────────
  TOTAL:               ~98 GB/mo scan reduction

This translates to faster queries and less warehouse credit consumption
from reduced compute time per query.
=============================================================================
*/
