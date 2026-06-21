-- ============================================================
-- 01_DATA_CLEANING.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Standardize, validate, and clean raw transaction data
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- STEP 1: Create a clean staging table from raw data
-- ─────────────────────────────────────────────────────────────
CREATE TABLE fraud_transactions_clean AS
SELECT
    -- Drop the unnamed index column, use trans_num as primary key
    trans_num                                          AS transaction_id,
    cc_num                                             AS card_number,

    -- Parse and standardize timestamp
    CAST(trans_date_trans_time AS TIMESTAMP)           AS transaction_ts,
    DATE(trans_date_trans_time)                        AS transaction_date,
    EXTRACT(HOUR FROM CAST(trans_date_trans_time AS TIMESTAMP)) AS transaction_hour,

    -- Strip the 'fraud_' prefix injected into merchant names
    REPLACE(merchant, 'fraud_', '')                    AS merchant_name,
    merchant                                           AS merchant_raw,
    category,

    -- Monetary amount (already float, ensure 2 dp precision)
    ROUND(CAST(amt AS DECIMAL(12,2)), 2)               AS amount,

    -- Customer identity
    first                                              AS first_name,
    last                                               AS last_name,
    CONCAT(first, ' ', last)                           AS full_name,
    UPPER(gender)                                      AS gender,
    dob                                                AS date_of_birth,

    -- Address fields
    street,
    city,
    UPPER(state)                                       AS state,
    CAST(zip AS VARCHAR(10))                           AS zip_code,

    -- Geo-coordinates (customer home)
    CAST(lat  AS DECIMAL(9,6))                         AS customer_lat,
    CAST(long AS DECIMAL(9,6))                         AS customer_long,

    -- Geo-coordinates (merchant location)
    CAST(merch_lat  AS DECIMAL(9,6))                   AS merchant_lat,
    CAST(merch_long AS DECIMAL(9,6))                   AS merchant_long,

    -- Demographic
    city_pop,
    job,
    unix_time,

    -- Target label
    CAST(is_fraud AS SMALLINT)                         AS is_fraud

FROM fraud_raw_transactions
WHERE
    -- Remove records with null critical fields
    trans_num             IS NOT NULL
    AND cc_num            IS NOT NULL
    AND trans_date_trans_time IS NOT NULL
    AND amt               IS NOT NULL
    AND is_fraud          IS NOT NULL
;


-- ─────────────────────────────────────────────────────────────
-- STEP 2: Duplicate detection
-- ─────────────────────────────────────────────────────────────

-- Find exact duplicate transaction IDs
SELECT
    transaction_id,
    COUNT(*) AS duplicate_count
FROM fraud_transactions_clean
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


-- ─────────────────────────────────────────────────────────────
-- STEP 3: Null / missing value audit
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                           AS total_rows,
    SUM(CASE WHEN transaction_id    IS NULL THEN 1 ELSE 0 END) AS null_transaction_id,
    SUM(CASE WHEN card_number       IS NULL THEN 1 ELSE 0 END) AS null_card_number,
    SUM(CASE WHEN transaction_ts    IS NULL THEN 1 ELSE 0 END) AS null_timestamp,
    SUM(CASE WHEN merchant_name     IS NULL THEN 1 ELSE 0 END) AS null_merchant,
    SUM(CASE WHEN category          IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN amount            IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN gender            IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN date_of_birth     IS NULL THEN 1 ELSE 0 END) AS null_dob,
    SUM(CASE WHEN state             IS NULL THEN 1 ELSE 0 END) AS null_state,
    SUM(CASE WHEN customer_lat      IS NULL THEN 1 ELSE 0 END) AS null_customer_lat,
    SUM(CASE WHEN merchant_lat      IS NULL THEN 1 ELSE 0 END) AS null_merchant_lat,
    SUM(CASE WHEN is_fraud          IS NULL THEN 1 ELSE 0 END) AS null_is_fraud
FROM fraud_transactions_clean;


-- ─────────────────────────────────────────────────────────────
-- STEP 4: Validate is_fraud only contains 0 or 1
-- ─────────────────────────────────────────────────────────────
SELECT
    is_fraud,
    COUNT(*) AS row_count
FROM fraud_transactions_clean
GROUP BY is_fraud
ORDER BY is_fraud;


-- ─────────────────────────────────────────────────────────────
-- STEP 5: Validate amount is positive and within plausible range
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                           AS total_rows,
    SUM(CASE WHEN amount <= 0    THEN 1 ELSE 0 END)   AS non_positive_amounts,
    SUM(CASE WHEN amount > 25000 THEN 1 ELSE 0 END)   AS extreme_high_amounts,
    MIN(amount)                                        AS min_amount,
    MAX(amount)                                        AS max_amount,
    AVG(amount)                                        AS avg_amount
FROM fraud_transactions_clean;


-- ─────────────────────────────────────────────────────────────
-- STEP 6: Validate geographic coordinates are in USA range
--   Lat: ~18 to 72 | Long: ~-168 to -66
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN customer_lat  NOT BETWEEN 18 AND 72   THEN 1 ELSE 0 END) AS bad_customer_lat,
    SUM(CASE WHEN customer_long NOT BETWEEN -168 AND -66 THEN 1 ELSE 0 END) AS bad_customer_long,
    SUM(CASE WHEN merchant_lat  NOT BETWEEN 18 AND 72   THEN 1 ELSE 0 END) AS bad_merchant_lat,
    SUM(CASE WHEN merchant_long NOT BETWEEN -168 AND -66 THEN 1 ELSE 0 END) AS bad_merchant_long
FROM fraud_transactions_clean;


-- ─────────────────────────────────────────────────────────────
-- STEP 7: Validate gender values
-- ─────────────────────────────────────────────────────────────
SELECT
    gender,
    COUNT(*) AS row_count
FROM fraud_transactions_clean
GROUP BY gender
ORDER BY gender;


-- ─────────────────────────────────────────────────────────────
-- STEP 8: Validate known category values
-- ─────────────────────────────────────────────────────────────
SELECT
    category,
    COUNT(*) AS row_count
FROM fraud_transactions_clean
WHERE category NOT IN (
    'entertainment', 'food_dining',    'gas_transport',
    'grocery_net',   'grocery_pos',    'health_fitness',
    'home',          'kids_pets',      'misc_net',
    'misc_pos',      'personal_care',  'shopping_net',
    'shopping_pos',  'travel'
)
GROUP BY category;


-- ─────────────────────────────────────────────────────────────
-- STEP 9: Date of birth sanity check (age 0–120)
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), CURRENT_DATE) < 0   THEN 1 ELSE 0 END) AS negative_age,
    SUM(CASE WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), CURRENT_DATE) > 120 THEN 1 ELSE 0 END) AS age_over_120,
    MIN(CAST(date_of_birth AS DATE)) AS oldest_dob,
    MAX(CAST(date_of_birth AS DATE)) AS youngest_dob
FROM fraud_transactions_clean;


-- ─────────────────────────────────────────────────────────────
-- STEP 10: Final validated view for downstream analysis
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_fraud_validated AS
SELECT *
FROM fraud_transactions_clean
WHERE
    amount > 0
    AND is_fraud IN (0, 1)
    AND customer_lat  BETWEEN 18  AND 72
    AND customer_long BETWEEN -168 AND -66
    AND merchant_lat  BETWEEN 18  AND 72
    AND merchant_long BETWEEN -168 AND -66
    AND gender IN ('M', 'F')
;
