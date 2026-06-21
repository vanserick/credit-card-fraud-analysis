-- ============================================================
-- 02_FEATURE_ENGINEERING.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Derive ML-ready and analytical features from raw data
-- Depends on: vw_fraud_validated (from 01_data_cleaning.sql)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- FEATURE 1: Customer age at time of transaction
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    card_number,
    date_of_birth,
    transaction_date,
    DATEDIFF('year',
        CAST(date_of_birth AS DATE),
        transaction_date
    )                                                  AS customer_age,
    CASE
        WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) < 25  THEN 'Under 25'
        WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) < 35  THEN '25-34'
        WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) < 45  THEN '35-44'
        WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) < 55  THEN '45-54'
        WHEN DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) < 65  THEN '55-64'
        ELSE '65+'
    END                                                AS age_group
FROM vw_fraud_validated;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 2: Time-of-day and day-of-week features
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    transaction_ts,
    transaction_hour,
    DAYOFWEEK(transaction_date)                        AS day_of_week,       -- 1=Sun, 7=Sat
    DAYNAME(transaction_date)                          AS day_name,
    CASE
        WHEN DAYOFWEEK(transaction_date) IN (1, 7)     THEN 1 ELSE 0
    END                                                AS is_weekend,
    CASE
        WHEN transaction_hour BETWEEN  0 AND  5  THEN 'Late Night'
        WHEN transaction_hour BETWEEN  6 AND 11  THEN 'Morning'
        WHEN transaction_hour BETWEEN 12 AND 17  THEN 'Afternoon'
        WHEN transaction_hour BETWEEN 18 AND 21  THEN 'Evening'
        ELSE 'Night'
    END                                                AS time_of_day,
    CASE
        WHEN transaction_hour BETWEEN  0 AND  5  THEN 1 ELSE 0
    END                                                AS is_late_night
FROM vw_fraud_validated;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 3: Haversine distance between customer home and merchant
--   Using simplified flat-earth approximation (adequate for SQL)
--   Full Haversine requires trigonometric functions
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    customer_lat,
    customer_long,
    merchant_lat,
    merchant_long,
    -- Euclidean approximation in degrees (fast proxy)
    SQRT(
        POWER(merchant_lat  - customer_lat,  2) +
        POWER(merchant_long - customer_long, 2)
    )                                                  AS geo_distance_deg,
    -- Approximate km (1 degree ≈ 111 km)
    SQRT(
        POWER((merchant_lat  - customer_lat)  * 111.0, 2) +
        POWER((merchant_long - customer_long) * 111.0 * COS(RADIANS(customer_lat)), 2)
    )                                                  AS geo_distance_km,
    CASE
        WHEN SQRT(
            POWER((merchant_lat  - customer_lat)  * 111.0, 2) +
            POWER((merchant_long - customer_long) * 111.0 * COS(RADIANS(customer_lat)), 2)
        ) > 100 THEN 1 ELSE 0
    END                                                AS is_far_from_home
FROM vw_fraud_validated;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 4: Amount-based features
-- ─────────────────────────────────────────────────────────────
WITH category_stats AS (
    SELECT
        category,
        AVG(amount)    AS cat_avg_amount,
        STDDEV(amount) AS cat_std_amount,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY amount) AS cat_median_amount,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount) AS cat_p95_amount
    FROM vw_fraud_validated
    GROUP BY category
)
SELECT
    t.transaction_id,
    t.amount,
    t.category,
    cs.cat_avg_amount,
    cs.cat_std_amount,
    -- Z-score of amount within its category
    (t.amount - cs.cat_avg_amount) / NULLIF(cs.cat_std_amount, 0) AS amount_z_score,
    -- Is this amount above the category 95th percentile?
    CASE WHEN t.amount > cs.cat_p95_amount THEN 1 ELSE 0 END      AS is_high_amount,
    -- Amount bucket (log scale)
    CASE
        WHEN t.amount < 10    THEN 'micro (<$10)'
        WHEN t.amount < 50    THEN 'small ($10-$50)'
        WHEN t.amount < 200   THEN 'medium ($50-$200)'
        WHEN t.amount < 1000  THEN 'large ($200-$1000)'
        ELSE 'very_large (>$1000)'
    END                                                            AS amount_bucket
FROM vw_fraud_validated t
JOIN category_stats cs ON t.category = cs.category;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 5: Card velocity — transaction count and spend per card
--   rolling 24-hour and 7-day windows
-- ─────────────────────────────────────────────────────────────
SELECT
    t.transaction_id,
    t.card_number,
    t.transaction_ts,
    t.amount,

    -- Number of transactions on the same card in the prior 24 hours
    COUNT(prev.transaction_id)                         AS txn_count_24h,
    -- Total spend on same card in the prior 24 hours
    COALESCE(SUM(prev.amount), 0)                      AS spend_24h,
    -- Max single transaction on same card in prior 24 hours
    COALESCE(MAX(prev.amount), 0)                      AS max_txn_24h

FROM vw_fraud_validated t
LEFT JOIN vw_fraud_validated prev
    ON  prev.card_number    = t.card_number
    AND prev.transaction_ts  > t.transaction_ts - INTERVAL '24' HOUR
    AND prev.transaction_ts  < t.transaction_ts
GROUP BY
    t.transaction_id, t.card_number, t.transaction_ts, t.amount;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 6: City population tier
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    city,
    state,
    city_pop,
    CASE
        WHEN city_pop <   5000  THEN 'Rural'
        WHEN city_pop <  25000  THEN 'Small Town'
        WHEN city_pop < 100000  THEN 'Mid-size City'
        WHEN city_pop < 500000  THEN 'Large City'
        ELSE 'Metro'
    END                                                AS city_tier
FROM vw_fraud_validated;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 7: Merchant repeat usage per card (loyalty signal)
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    merchant_name,
    COUNT(*)          AS visit_count,
    SUM(amount)       AS total_spend,
    MIN(transaction_ts) AS first_visit,
    MAX(transaction_ts) AS last_visit,
    CASE WHEN COUNT(*) > 1 THEN 1 ELSE 0 END AS is_repeat_merchant
FROM vw_fraud_validated
GROUP BY card_number, merchant_name
ORDER BY visit_count DESC;


-- ─────────────────────────────────────────────────────────────
-- FEATURE 8: Combine all engineered features into one wide table
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_fraud_features AS
WITH age_feat AS (
    SELECT
        transaction_id,
        DATEDIFF('year', CAST(date_of_birth AS DATE), transaction_date) AS customer_age
    FROM vw_fraud_validated
),
time_feat AS (
    SELECT
        transaction_id,
        DAYOFWEEK(transaction_date) AS day_of_week,
        CASE WHEN DAYOFWEEK(transaction_date) IN (1,7) THEN 1 ELSE 0 END AS is_weekend,
        CASE WHEN transaction_hour BETWEEN 0 AND 5 THEN 1 ELSE 0 END     AS is_late_night
    FROM vw_fraud_validated
),
geo_feat AS (
    SELECT
        transaction_id,
        SQRT(
            POWER((merchant_lat  - customer_lat)  * 111.0, 2) +
            POWER((merchant_long - customer_long) * 111.0 * COS(RADIANS(customer_lat)), 2)
        ) AS geo_distance_km
    FROM vw_fraud_validated
),
cat_stats AS (
    SELECT category,
        AVG(amount)    AS cat_avg,
        STDDEV(amount) AS cat_std
    FROM vw_fraud_validated GROUP BY category
)
SELECT
    v.*,
    af.customer_age,
    tf.day_of_week,
    tf.is_weekend,
    tf.is_late_night,
    gf.geo_distance_km,
    CASE WHEN gf.geo_distance_km > 100 THEN 1 ELSE 0 END AS is_far_from_home,
    (v.amount - cs.cat_avg) / NULLIF(cs.cat_std, 0)      AS amount_z_score,
    CASE
        WHEN v.city_pop <   5000  THEN 'Rural'
        WHEN v.city_pop <  25000  THEN 'Small Town'
        WHEN v.city_pop < 100000  THEN 'Mid-size City'
        WHEN v.city_pop < 500000  THEN 'Large City'
        ELSE 'Metro'
    END                                                   AS city_tier
FROM vw_fraud_validated v
JOIN age_feat  af ON af.transaction_id = v.transaction_id
JOIN time_feat tf ON tf.transaction_id = v.transaction_id
JOIN geo_feat  gf ON gf.transaction_id = v.transaction_id
JOIN cat_stats cs ON cs.category       = v.category;
