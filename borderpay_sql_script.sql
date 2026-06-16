-- ================================================================
-- BorderPay: Revenue Leak Audit
-- Tool: MySQL
-- Author: Ima-Abasi
--
-- BorderPay is a cross-border payments platform serving
-- freelancers and remote workers across Africa, Asia, and
-- Latin America. This script investigates where the platform
-- is silently losing revenue through failed transactions,
-- frustrated users, and overwhelmed support teams.
--
-- The analysis powers a three-page Power BI dashboard built
-- for executive leadership -- covering revenue leakage,
-- customer friction, and recovery prioritization.
--
-- Phases:
--   0. Database Setup
--   1. Diagnostic Checks
--   2. Data Cleaning
--   3. Business Analysis
-- ================================================================


-- ================================================================
-- PHASE 0: DATABASE SETUP
-- ================================================================

CREATE DATABASE IF NOT EXISTS borderpay;
USE borderpay;


-- ================================================================
-- PHASE 1: DIAGNOSTIC CHECKS
-- ================================================================
-- Before touching anything, we audit each raw table to understand
-- exactly what problems exist. This is the SQL equivalent of
-- column profiling in Power Query -- inspect first, fix second.
-- ================================================================


-- TRANSACTIONS ------------------------------------------------

-- Baseline row count
SELECT COUNT(*) AS total_rows FROM transactions;

-- How many duplicates?
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT transaction_id) AS unique_transactions,
    COUNT(*) - COUNT(DISTINCT transaction_id) AS duplicate_count
FROM transactions;

-- Which columns have NULL or blank values?
SELECT
    SUM(CASE WHEN transaction_id IS NULL OR TRIM(transaction_id) = '' THEN 1 ELSE 0 END) AS null_transaction_id,
    SUM(CASE WHEN user_id IS NULL OR TRIM(user_id) = '' THEN 1 ELSE 0 END) AS null_user_id,
    SUM(CASE WHEN transaction_date IS NULL OR TRIM(transaction_date) = '' THEN 1 ELSE 0 END) AS null_transaction_date,
    SUM(CASE WHEN amount_usd IS NULL OR TRIM(amount_usd) = '' THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN settled_amount_usd IS NULL OR TRIM(settled_amount_usd) = '' THEN 1 ELSE 0 END) AS null_settled_amount,
    SUM(CASE WHEN corridor IS NULL OR TRIM(corridor) = '' THEN 1 ELSE 0 END) AS null_corridor,
    SUM(CASE WHEN transaction_status IS NULL OR TRIM(transaction_status) = '' THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN failure_reason IS NULL OR TRIM(failure_reason) = '' THEN 1 ELSE 0 END) AS null_failure_reason
FROM transactions;

-- All distinct status values -- reveals typos and casing issues
SELECT transaction_status, COUNT(*) AS frequency
FROM transactions
GROUP BY transaction_status
ORDER BY frequency DESC;

-- All distinct failure reasons
SELECT failure_reason, COUNT(*) AS frequency
FROM transactions
GROUP BY failure_reason
ORDER BY frequency DESC;

-- Corridor whitespace check
SELECT COUNT(*) AS whitespace_corridor_count
FROM transactions
WHERE corridor != TRIM(corridor);

-- Failed transactions missing a failure reason
SELECT COUNT(*) AS failed_with_no_reason
FROM transactions
WHERE UPPER(TRIM(transaction_status)) = 'FAILED'
  AND (failure_reason IS NULL OR TRIM(failure_reason) = '');

-- Settled transactions missing a settled amount
SELECT COUNT(*) AS settled_with_no_amount
FROM transactions
WHERE UPPER(TRIM(transaction_status)) = 'SETTLED'
  AND (settled_amount_usd IS NULL OR TRIM(settled_amount_usd) = '');

-- What date formats are present?
SELECT DISTINCT transaction_date FROM transactions LIMIT 20;

-- Dates that fail the standard conversion -- reveals other formats
SELECT DISTINCT transaction_date
FROM transactions
WHERE STR_TO_DATE(transaction_date, '%m/%d/%Y %H:%i') IS NULL
LIMIT 20;


-- USERS -------------------------------------------------------

SELECT COUNT(*) AS total_rows FROM users;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(*) - COUNT(DISTINCT user_id) AS duplicate_count
FROM users;

SELECT
    SUM(CASE WHEN user_id IS NULL OR TRIM(user_id) = '' THEN 1 ELSE 0 END) AS null_user_id,
    SUM(CASE WHEN full_name IS NULL OR TRIM(full_name) = '' THEN 1 ELSE 0 END) AS null_full_name,
    SUM(CASE WHEN email IS NULL OR TRIM(email) = '' THEN 1 ELSE 0 END) AS null_email,
    SUM(CASE WHEN country IS NULL OR TRIM(country) = '' THEN 1 ELSE 0 END) AS null_country,
    SUM(CASE WHEN registration_date IS NULL OR TRIM(registration_date) = '' THEN 1 ELSE 0 END) AS null_registration_date,
    SUM(CASE WHEN account_status IS NULL OR TRIM(account_status) = '' THEN 1 ELSE 0 END) AS null_account_status
FROM users;

SELECT account_status, COUNT(*) AS frequency
FROM users
GROUP BY account_status
ORDER BY frequency DESC;

SELECT country, COUNT(*) AS frequency
FROM users
GROUP BY country
ORDER BY frequency DESC;


-- RETRIES -----------------------------------------------------

SELECT COUNT(*) AS total_rows FROM retries;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT retry_id) AS unique_retries,
    COUNT(*) - COUNT(DISTINCT retry_id) AS duplicate_count
FROM retries;

SELECT retry_status, COUNT(*) AS frequency
FROM retries
GROUP BY retry_status
ORDER BY frequency DESC;


-- USER ACTIVITY -----------------------------------------------

SELECT COUNT(*) AS total_rows FROM user_activity;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT activity_id) AS unique_activities,
    COUNT(*) - COUNT(DISTINCT activity_id) AS duplicate_count
FROM user_activity;

SELECT activity_type, COUNT(*) AS frequency
FROM user_activity
GROUP BY activity_type
ORDER BY frequency DESC;


-- SUPPORT TICKETS ---------------------------------------------

SELECT COUNT(*) AS total_rows FROM support_tickets;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT ticket_id) AS unique_tickets,
    COUNT(*) - COUNT(DISTINCT ticket_id) AS duplicate_count
FROM support_tickets;

SELECT resolution_status, COUNT(*) AS frequency
FROM support_tickets
GROUP BY resolution_status
ORDER BY frequency DESC;

SELECT ticket_category, COUNT(*) AS frequency
FROM support_tickets
GROUP BY ticket_category
ORDER BY frequency DESC;


-- ================================================================
-- PHASE 2: DATA CLEANING
-- ================================================================
-- Raw data is never perfect. The five imported tables contain
-- duplicate rows, inconsistent date formats, text casing issues,
-- blank values, whitespace errors, and misspelled country names.
--
-- We never modify the raw tables. Instead we create a clean
-- version of each table using CREATE TABLE AS SELECT.
-- This preserves the original data and gives us a safe,
-- analysis-ready copy for all downstream work.
--
-- Issues fixed across all tables:
--   - Duplicates removed using ROW_NUMBER()
--   - Dates converted from text to DATETIME using STR_TO_DATE()
--   - Status values standardised using CASE WHEN + UPPER + TRIM
--   - Blank values replaced using COALESCE and NULLIF
--   - Country misspellings corrected
--   - Corridor rebuilt cleanly from sender and receiver currency
--   - Hour of Day extracted for time-based failure analysis
-- ================================================================


-- TABLE 1: transactions_clean ---------------------------------

CREATE TABLE transactions_clean AS

WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY transaction_id
               ORDER BY transaction_date
           ) AS row_num
    FROM transactions
),

no_duplicates AS (
    SELECT * FROM deduplicated WHERE row_num = 1
)

SELECT
    transaction_id,
    user_id,

    -- Two date formats were found in the raw data.
    -- We detect each format using LIKE and convert to DATETIME.
    CASE
        WHEN transaction_date LIKE '%/%'
            THEN STR_TO_DATE(transaction_date, '%m/%d/%Y %H:%i')
        WHEN transaction_date LIKE '%-%'
            THEN STR_TO_DATE(transaction_date, '%d-%m-%Y %H:%i:%s')
        ELSE NULL
    END AS transaction_date,

    amount_usd,

    COALESCE(NULLIF(TRIM(settled_amount_usd), ''), '0.00') AS settled_amount_usd,

    sender_currency,
    receiver_currency,

    -- The corridor column had encoding issues from the CSV import.
    -- We rebuild it cleanly from the two currency columns.
    CONCAT(sender_currency, ' - ', receiver_currency) AS corridor,

    CASE
        WHEN UPPER(TRIM(transaction_status)) IN ('SETTLED', 'SETTELD', 'SETTLD') THEN 'Settled'
        WHEN UPPER(TRIM(transaction_status)) IN ('FAILED', 'FAILD', 'FAILLD') THEN 'Failed'
        WHEN UPPER(TRIM(transaction_status)) IN ('PROCESSING', 'PROCESING', 'PROCCESSING') THEN 'Processing'
        WHEN UPPER(TRIM(transaction_status)) IN ('REVERSED', 'REVERSERD', 'REVERSD') THEN 'Reversed'
        ELSE 'Unknown'
    END AS transaction_status,

    COALESCE(NULLIF(TRIM(failure_reason), ''), 'Unclassified') AS failure_reason,

    processing_time_sec,

    -- Extracted for the time-based failure analysis on Page 3.
    HOUR(
        CASE
            WHEN transaction_date LIKE '%/%'
                THEN STR_TO_DATE(transaction_date, '%m/%d/%Y %H:%i')
            WHEN transaction_date LIKE '%-%'
                THEN STR_TO_DATE(transaction_date, '%d-%m-%Y %H:%i:%s')
            ELSE NULL
        END
    ) AS hour_of_day

FROM no_duplicates;

-- Verify
SELECT COUNT(*) AS clean_transaction_count FROM transactions_clean;
SELECT transaction_status, COUNT(*) AS frequency
FROM transactions_clean
GROUP BY transaction_status
ORDER BY frequency DESC;


-- TABLE 2: users_clean ----------------------------------------

CREATE TABLE users_clean AS

WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY registration_date
           ) AS row_num
    FROM users
),

no_duplicates AS (
    SELECT * FROM deduplicated WHERE row_num = 1
)

SELECT
    user_id,
    full_name,

    COALESCE(NULLIF(TRIM(email), ''), 'Not Provided') AS email,

    CASE
        WHEN UPPER(TRIM(country)) IN ('NIGERIA', 'NIGRIA', 'NIGERRIA') THEN 'Nigeria'
        WHEN UPPER(TRIM(country)) IN ('KENYA', 'KENY', 'KENIA') THEN 'Kenya'
        WHEN UPPER(TRIM(country)) IN ('GHANA', 'GHANNA', 'GANA') THEN 'Ghana'
        WHEN UPPER(TRIM(country)) IN ('INDIA', 'INDA', 'INDAI') THEN 'India'
        WHEN UPPER(TRIM(country)) IN ('PHILIPPINES', 'PHILLIPINES', 'PHILIPINES') THEN 'Philippines'
        WHEN UPPER(TRIM(country)) IN ('BRAZIL', 'BRASIL', 'BRAZILL') THEN 'Brazil'
        WHEN UPPER(TRIM(country)) IN ('PAKISTAN', 'PAKSTAN', 'PAKISTANN') THEN 'Pakistan'
        WHEN UPPER(TRIM(country)) IN ('BANGLADESH', 'BANGLDESH', 'BANGLADSH') THEN 'Bangladesh'
        ELSE TRIM(country)
    END AS country,

    -- All registration dates were in M/D/YYYY format.
    STR_TO_DATE(registration_date, '%m/%d/%Y') AS registration_date,

    CASE
        WHEN UPPER(TRIM(account_status)) IN ('ACTIVE', 'ACTVE', 'ACTIV') THEN 'Active'
        WHEN UPPER(TRIM(account_status)) IN ('INACTIVE', 'INACTVE', 'INACTIV') THEN 'Inactive'
        WHEN UPPER(TRIM(account_status)) IN ('SUSPENDED', 'SUSPNDED', 'SUSPENDD') THEN 'Suspended'
        ELSE 'Unknown'
    END AS account_status

FROM no_duplicates;

-- Verify
SELECT COUNT(*) AS clean_user_count FROM users_clean;
SELECT DISTINCT country FROM users_clean ORDER BY country;


-- TABLE 3: retries_clean --------------------------------------

CREATE TABLE retries_clean AS

WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY retry_id
               ORDER BY retry_timestamp
           ) AS row_num
    FROM retries
),

no_duplicates AS (
    SELECT * FROM deduplicated WHERE row_num = 1
)

SELECT
    retry_id,
    original_transaction_id,
    user_id,

    CASE
        WHEN retry_timestamp LIKE '%/%'
            THEN STR_TO_DATE(retry_timestamp, '%m/%d/%Y %H:%i')
        WHEN retry_timestamp LIKE '%-%'
            THEN STR_TO_DATE(retry_timestamp, '%d-%m-%Y %H:%i:%s')
        ELSE NULL
    END AS retry_timestamp,

    amount_usd,

    CASE
        WHEN UPPER(TRIM(retry_status)) IN ('SETTLED', 'SETTELD', 'SETTLD') THEN 'Settled'
        WHEN UPPER(TRIM(retry_status)) IN ('FAILED', 'FAILD', 'FAILLD') THEN 'Failed'
        ELSE 'Unknown'
    END AS retry_status,

    COALESCE(NULLIF(TRIM(failure_reason), ''), 'Unclassified') AS failure_reason,

    retry_number

FROM no_duplicates;

-- Verify
SELECT COUNT(*) AS clean_retry_count FROM retries_clean;


-- TABLE 4: user_activity_clean --------------------------------

CREATE TABLE user_activity_clean AS

WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY activity_id
               ORDER BY activity_timestamp
           ) AS row_num
    FROM user_activity
),

no_duplicates AS (
    SELECT * FROM deduplicated WHERE row_num = 1
)

SELECT
    activity_id,
    user_id,

    COALESCE(NULLIF(TRIM(activity_type), ''), 'Unclassified') AS activity_type,

    CASE
        WHEN activity_timestamp LIKE '%/%'
            THEN STR_TO_DATE(activity_timestamp, '%m/%d/%Y %H:%i')
        WHEN activity_timestamp LIKE '%-%'
            THEN STR_TO_DATE(activity_timestamp, '%d-%m-%Y %H:%i:%s')
        ELSE NULL
    END AS activity_timestamp,

    -- Note: Country standardisation for this table was completed
    -- in Power Query due to a character encoding conflict in MySQL
    -- that prevented UPPER and TRIM from matching stored values.
    country

FROM no_duplicates;

-- Verify
SELECT COUNT(*) AS clean_activity_count FROM user_activity_clean;
SELECT DISTINCT activity_type FROM user_activity_clean;


-- TABLE 5: support_tickets_clean ------------------------------

CREATE TABLE support_tickets_clean AS

WITH deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY ticket_id
               ORDER BY ticket_timestamp
           ) AS row_num
    FROM support_tickets
),

no_duplicates AS (
    SELECT * FROM deduplicated WHERE row_num = 1
)

SELECT
    ticket_id,
    user_id,
    related_transaction_id,

    CASE
        WHEN ticket_timestamp LIKE '%/%'
            THEN STR_TO_DATE(ticket_timestamp, '%m/%d/%Y %H:%i')
        WHEN ticket_timestamp LIKE '%-%'
            THEN STR_TO_DATE(ticket_timestamp, '%d-%m-%Y %H:%i:%s')
        ELSE NULL
    END AS ticket_timestamp,

    COALESCE(NULLIF(TRIM(ticket_category), ''), 'Unclassified') AS ticket_category,

    -- Note: Country standardisation completed in Power Query.
    country,

    CASE
        WHEN UPPER(TRIM(resolution_status)) IN ('RESOLVED', 'RESOLVD', 'RESOLV') THEN 'Resolved'
        WHEN UPPER(TRIM(resolution_status)) IN ('PENDING', 'PENDIN', 'PENDNG') THEN 'Pending'
        WHEN UPPER(TRIM(resolution_status)) IN ('ESCALATED', 'ESCALTD', 'ESCALATD') THEN 'Escalated'
        ELSE 'Unknown'
    END AS resolution_status

FROM no_duplicates;

-- Verify
SELECT COUNT(*) AS clean_ticket_count FROM support_tickets_clean;
SELECT DISTINCT resolution_status FROM support_tickets_clean;


-- ================================================================
-- PHASE 3: BUSINESS ANALYSIS
-- ================================================================
-- Six queries that answer the core business questions driving
-- the Power BI dashboard. All queries read from clean tables only.
-- ================================================================


-- Q1: Revenue Leakage -----------------------------------------
-- How much transaction value was attempted vs successfully settled?

SELECT
    COUNT(*) AS total_transactions,
    COUNT(CASE WHEN transaction_status = 'Settled' THEN 1 END) AS successful_transactions,
    COUNT(CASE WHEN transaction_status = 'Failed' THEN 1 END) AS failed_transactions,
    ROUND(SUM(amount_usd), 2) AS total_attempted_volume,
    ROUND(SUM(CASE WHEN transaction_status = 'Settled' THEN amount_usd ELSE 0 END), 2) AS total_settled_volume,
    ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN amount_usd ELSE 0 END), 2) AS failed_volume,
    ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN amount_usd ELSE 0 END) / SUM(amount_usd) * 100, 2) AS revenue_leakage_rate_pct
FROM transactions_clean;


-- Q2: Retry Behaviour -----------------------------------------
-- When payments fail, do users recover or give up?
--
-- A recovered user is one who had at least one successful retry
-- across any of their failed transactions.

WITH retry_summary AS (
    SELECT
        user_id,
        original_transaction_id,
        COUNT(*) AS total_retries,
        MAX(CASE WHEN retry_status = 'Settled' THEN 1 ELSE 0 END) AS ever_recovered
    FROM retries_clean
    GROUP BY user_id, original_transaction_id
),

user_level AS (
    SELECT
        user_id,
        ROUND(AVG(total_retries), 2) AS avg_retries,
        MAX(ever_recovered) AS ever_recovered
    FROM retry_summary
    GROUP BY user_id
)

SELECT
    COUNT(DISTINCT user_id) AS total_users_who_retried,
    ROUND(AVG(avg_retries), 2) AS avg_retries_per_user,
    SUM(CASE WHEN ever_recovered = 1 THEN 1 ELSE 0 END) AS recovered_users,
    SUM(CASE WHEN ever_recovered = 0 THEN 1 ELSE 0 END) AS abandoned_users,
    ROUND(SUM(CASE WHEN ever_recovered = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT user_id) * 100, 2) AS recovery_rate_pct,
    ROUND(SUM(CASE WHEN ever_recovered = 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT user_id) * 100, 2) AS abandonment_rate_pct
FROM user_level;


-- Q3: Customer Abandonment ------------------------------------
-- Which failures are causing customers to permanently leave?
--
-- Abandonment threshold: 30 days of inactivity after last failure.
-- The 30-day window accounts for freelancers who may simply
-- be between projects rather than churned.

WITH last_failure AS (
    SELECT
        user_id,
        MAX(transaction_date) AS last_failure_date,
        COUNT(*) AS total_failures,
        SUM(amount_usd) AS failed_amount
    FROM transactions_clean
    WHERE transaction_status = 'Failed'
    GROUP BY user_id
),

last_activity AS (
    SELECT
        user_id,
        MAX(activity_timestamp) AS last_activity_date
    FROM user_activity_clean
    GROUP BY user_id
),

abandonment_check AS (
    SELECT
        lf.user_id,
        lf.last_failure_date,
        lf.total_failures,
        lf.failed_amount,
        la.last_activity_date,
        DATEDIFF(la.last_activity_date, lf.last_failure_date) AS days_active_after_failure
    FROM last_failure lf
    LEFT JOIN last_activity la ON lf.user_id = la.user_id
),

classified AS (
    SELECT
        user_id,
        last_failure_date,
        last_activity_date,
        total_failures,
        failed_amount,
        days_active_after_failure,
        CASE
            WHEN days_active_after_failure IS NULL THEN 'Abandoned'
            WHEN days_active_after_failure <= 30 THEN 'Abandoned'
            ELSE 'Active'
        END AS abandonment_status
    FROM abandonment_check
)

SELECT
    COUNT(DISTINCT user_id) AS total_users_with_failures,
    SUM(CASE WHEN abandonment_status = 'Abandoned' THEN 1 ELSE 0 END) AS abandoned_users,
    SUM(CASE WHEN abandonment_status = 'Active' THEN 1 ELSE 0 END) AS active_users,
    ROUND(SUM(CASE WHEN abandonment_status = 'Abandoned' THEN 1 ELSE 0 END) / COUNT(DISTINCT user_id) * 100, 2) AS abandonment_rate_pct,
    ROUND(SUM(CASE WHEN abandonment_status = 'Abandoned' THEN failed_amount ELSE 0 END), 2) AS revenue_at_risk
FROM classified;


-- Q4: Payment Corridor Performance ----------------------------
-- Which payment routes are underperforming?

WITH corridor_stats AS (
    SELECT
        corridor,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN transaction_status = 'Settled' THEN 1 ELSE 0 END) AS successful_transactions,
        SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) AS failed_transactions,
        ROUND(SUM(amount_usd), 2) AS total_attempted_volume,
        ROUND(SUM(CASE WHEN transaction_status = 'Settled' THEN amount_usd ELSE 0 END), 2) AS settled_volume,
        ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN amount_usd ELSE 0 END), 2) AS failed_volume,
        ROUND(AVG(processing_time_sec), 2) AS avg_processing_time_sec
    FROM transactions_clean
    GROUP BY corridor
),

corridor_rates AS (
    SELECT
        corridor,
        total_transactions,
        successful_transactions,
        failed_transactions,
        total_attempted_volume,
        settled_volume,
        failed_volume,
        avg_processing_time_sec,
        ROUND(successful_transactions / total_transactions * 100, 2) AS success_rate_pct,
        ROUND(failed_transactions / total_transactions * 100, 2) AS failure_rate_pct,
        ROUND(failed_volume / total_attempted_volume * 100, 2) AS revenue_leakage_rate_pct
    FROM corridor_stats
)

SELECT
    corridor,
    total_transactions,
    successful_transactions,
    failed_transactions,
    success_rate_pct,
    failure_rate_pct,
    total_attempted_volume,
    settled_volume,
    failed_volume,
    revenue_leakage_rate_pct,
    avg_processing_time_sec,
    RANK() OVER (ORDER BY failure_rate_pct DESC) AS failure_rank
FROM corridor_rates
ORDER BY failure_rank;


-- Q5: Time-Based Failure Analysis -----------------------------
-- Are there specific hours or days where failures consistently
-- spike -- pointing to banking downtime or infrastructure issues?

WITH hourly_failures AS (
    SELECT
        HOUR(transaction_date) AS hour_of_day,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) AS failed_transactions,
        ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS failure_rate_pct
    FROM transactions_clean
    GROUP BY HOUR(transaction_date)
),

daily_failures AS (
    SELECT
        DAYOFWEEK(transaction_date) AS day_number,
        CASE DAYOFWEEK(transaction_date)
            WHEN 1 THEN 'Sunday'
            WHEN 2 THEN 'Monday'
            WHEN 3 THEN 'Tuesday'
            WHEN 4 THEN 'Wednesday'
            WHEN 5 THEN 'Thursday'
            WHEN 6 THEN 'Friday'
            WHEN 7 THEN 'Saturday'
        END AS day_of_week,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) AS failed_transactions,
        ROUND(SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS failure_rate_pct
    FROM transactions_clean
    GROUP BY
        DAYOFWEEK(transaction_date),
        CASE DAYOFWEEK(transaction_date)
            WHEN 1 THEN 'Sunday'
            WHEN 2 THEN 'Monday'
            WHEN 3 THEN 'Tuesday'
            WHEN 4 THEN 'Wednesday'
            WHEN 5 THEN 'Thursday'
            WHEN 6 THEN 'Friday'
            WHEN 7 THEN 'Saturday'
        END
),

combined AS (
    SELECT 'Hourly' AS analysis_type, hour_of_day AS time_period, NULL AS day_name,
           total_transactions, failed_transactions, failure_rate_pct
    FROM hourly_failures

    UNION ALL

    SELECT 'Daily' AS analysis_type, day_number AS time_period, day_of_week AS day_name,
           total_transactions, failed_transactions, failure_rate_pct
    FROM daily_failures
)

SELECT * FROM combined ORDER BY analysis_type, time_period;


-- Q6: Support Burden Analysis ---------------------------------
-- How much operational workload is created by transaction failures?

WITH failure_counts AS (
    SELECT
        uc.country,
        COUNT(*) AS total_failed_transactions
    FROM transactions_clean tc
    JOIN users_clean uc ON tc.user_id = uc.user_id
    WHERE tc.transaction_status = 'Failed'
    GROUP BY uc.country
),

ticket_counts AS (
    SELECT
        country,
        COUNT(*) AS total_tickets,
        SUM(CASE WHEN ticket_category = 'Payment Not Received' THEN 1 ELSE 0 END) AS payment_not_received,
        SUM(CASE WHEN ticket_category = 'Transaction Stuck in Processing' THEN 1 ELSE 0 END) AS stuck_in_processing,
        SUM(CASE WHEN ticket_category = 'Wrong Amount Settled' THEN 1 ELSE 0 END) AS wrong_amount_settled,
        SUM(CASE WHEN ticket_category = 'Account Suspended After Failure' THEN 1 ELSE 0 END) AS account_suspended,
        SUM(CASE WHEN ticket_category = 'Refund Request' THEN 1 ELSE 0 END) AS refund_request,
        SUM(CASE WHEN ticket_category = 'Duplicate Charge' THEN 1 ELSE 0 END) AS duplicate_charge,
        SUM(CASE WHEN ticket_category = 'Failed Verification' THEN 1 ELSE 0 END) AS failed_verification,
        SUM(CASE WHEN ticket_category = 'Unclassified' THEN 1 ELSE 0 END) AS unclassified
    FROM support_tickets_clean
    GROUP BY country
)

SELECT
    fc.country,
    fc.total_failed_transactions,
    tc.total_tickets,
    ROUND(tc.total_tickets / fc.total_failed_transactions * 1000, 2) AS tickets_per_1000_failures,
    tc.payment_not_received,
    tc.stuck_in_processing,
    tc.wrong_amount_settled,
    tc.account_suspended,
    tc.refund_request,
    tc.duplicate_charge,
    tc.failed_verification,
    tc.unclassified
FROM failure_counts fc
JOIN ticket_counts tc ON fc.country = tc.country
ORDER BY tickets_per_1000_failures DESC;


-- ================================================================
-- END OF SCRIPT
-- ================================================================
-- Clean tables: 5
-- Analysis queries: 6
-- SQL skills demonstrated:
--   CTEs, Window Functions, Conditional Aggregation,
--   STR_TO_DATE, COALESCE, NULLIF, TRIM, UPPER, CONCAT,
--   HOUR, DAYOFWEEK, ROW_NUMBER, RANK, DATEDIFF,
--   LEFT JOIN, INNER JOIN, UNION ALL, GROUP BY
-- ================================================================
