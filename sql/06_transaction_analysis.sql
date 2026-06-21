-- ============================================================
-- 06_TRANSACTION_ANALYSIS.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Deep-dive into individual transaction patterns,
--          anomaly detection, and time-series analysis
-- Depends on: vw_fraud_features (from 02_feature_engineering.sql)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- QUERY 1: Transaction amount distribution — fraud vs legit
-- ─────────────────────────────────────────────────────────────
SELECT
    is_fraud,
    CASE WHEN is_fraud = 1 THEN 'Fraudulent' ELSE 'Legitimate' END AS label,
    COUNT(*)                                           AS txn_count,
    ROUND(AVG(amount), 2)                              AS avg_amount,
    ROUND(MIN(amount), 2)                              AS min_amount,
    ROUND(MAX(amount), 2)                              AS max_amount,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount), 2) AS p25_amount,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY amount), 2) AS median_amount,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount), 2) AS p75_amount,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount), 2) AS p95_amount,
    ROUND(STDDEV(amount), 2)                           AS std_amount
FROM vw_fraud_features
GROUP BY is_fraud;


-- ─────────────────────────────────────────────────────────────
-- QUERY 2: Transaction amount histogram (buckets)
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN amount <    10  THEN '1. $0–$10'
        WHEN amount <    25  THEN '2. $10–$25'
        WHEN amount <    50  THEN '3. $25–$50'
        WHEN amount <   100  THEN '4. $50–$100'
        WHEN amount <   200  THEN '5. $100–$200'
        WHEN amount <   500  THEN '6. $200–$500'
        WHEN amount <  1000  THEN '7. $500–$1,000'
        ELSE                      '8. $1,000+'
    END                                                AS amount_bucket,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_value
FROM vw_fraud_features
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────
-- QUERY 3: Fraud transactions with extreme amount z-scores (>2 std)
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    transaction_ts,
    card_number,
    full_name,
    merchant_name,
    category,
    amount,
    ROUND(amount_z_score, 2)                           AS amount_z_score,
    geo_distance_km,
    is_late_night,
    is_far_from_home,
    is_fraud
FROM vw_fraud_features
WHERE ABS(amount_z_score) > 2
ORDER BY amount_z_score DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 4: Fraud rate by category and amount bucket (cross-tab)
-- ─────────────────────────────────────────────────────────────
SELECT
    category,
    CASE
        WHEN amount <   50  THEN 'Low (<$50)'
        WHEN amount <  200  THEN 'Medium ($50–$200)'
        ELSE                     'High (>$200)'
    END                                                AS amount_tier,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct
FROM vw_fraud_features
GROUP BY category, 2
ORDER BY category, 2;


-- ─────────────────────────────────────────────────────────────
-- QUERY 5: Time-series — daily transaction and fraud volume
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_date,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_value,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value
FROM vw_fraud_features
GROUP BY transaction_date
ORDER BY transaction_date;


-- ─────────────────────────────────────────────────────────────
-- QUERY 6: 7-day rolling average fraud rate
-- ─────────────────────────────────────────────────────────────
WITH daily AS (
    SELECT
        transaction_date,
        COUNT(*)            AS total_txns,
        SUM(is_fraud)       AS fraud_count
    FROM vw_fraud_features
    GROUP BY transaction_date
)
SELECT
    transaction_date,
    total_txns,
    fraud_count,
    ROUND(fraud_count * 100.0 / total_txns, 4)        AS daily_fraud_rate_pct,
    ROUND(AVG(fraud_count * 100.0 / total_txns)
          OVER (ORDER BY transaction_date
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 4) AS fraud_rate_7d_avg
FROM daily
ORDER BY transaction_date;


-- ─────────────────────────────────────────────────────────────
-- QUERY 7: Fraud by day of week and hour (heat-map matrix)
-- ─────────────────────────────────────────────────────────────
SELECT
    DAYNAME(transaction_date)                          AS day_name,
    day_of_week,
    transaction_hour,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct
FROM vw_fraud_features
GROUP BY day_name, day_of_week, transaction_hour
ORDER BY day_of_week, transaction_hour;


-- ─────────────────────────────────────────────────────────────
-- QUERY 8: Merchant-level transaction analysis
-- ─────────────────────────────────────────────────────────────
SELECT
    merchant_name,
    category,
    COUNT(*)                                           AS total_txns,
    COUNT(DISTINCT card_number)                        AS unique_customers,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_revenue,
    ROUND(AVG(amount), 2)                              AS avg_transaction,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value,
    ROUND(AVG(geo_distance_km), 1)                     AS avg_customer_distance_km
FROM vw_fraud_features
GROUP BY merchant_name, category
ORDER BY fraud_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 9: Rapid-fire transactions — same card, within 5 minutes
--   Indicator of card testing / automated fraud
-- ─────────────────────────────────────────────────────────────
SELECT
    t1.card_number,
    t1.full_name,
    t1.transaction_id                                  AS txn_1_id,
    t2.transaction_id                                  AS txn_2_id,
    t1.transaction_ts                                  AS txn_1_time,
    t2.transaction_ts                                  AS txn_2_time,
    DATEDIFF('second', t1.transaction_ts, t2.transaction_ts) AS seconds_apart,
    t1.amount                                          AS txn_1_amount,
    t2.amount                                          AS txn_2_amount,
    t1.merchant_name                                   AS txn_1_merchant,
    t2.merchant_name                                   AS txn_2_merchant,
    t1.is_fraud                                        AS txn_1_fraud,
    t2.is_fraud                                        AS txn_2_fraud
FROM vw_fraud_features t1
JOIN vw_fraud_features t2
    ON  t2.card_number    = t1.card_number
    AND t2.transaction_ts > t1.transaction_ts
    AND t2.transaction_ts <= t1.transaction_ts + INTERVAL '5' MINUTE
    AND t2.transaction_id != t1.transaction_id
ORDER BY t1.card_number, t1.transaction_ts;


-- ─────────────────────────────────────────────────────────────
-- QUERY 10: Top fraud transactions ranked by amount
-- ─────────────────────────────────────────────────────────────
SELECT
    ROW_NUMBER() OVER (ORDER BY amount DESC)           AS rank,
    transaction_id,
    transaction_ts,
    card_number,
    full_name,
    merchant_name,
    category,
    ROUND(amount, 2)                                   AS amount,
    state,
    ROUND(geo_distance_km, 1)                          AS distance_km,
    is_late_night,
    ROUND(amount_z_score, 2)                           AS amount_z_score
FROM vw_fraud_features
WHERE is_fraud = 1
ORDER BY amount DESC
LIMIT 50;


-- ─────────────────────────────────────────────────────────────
-- QUERY 11: Cumulative fraud value over time
-- ─────────────────────────────────────────────────────────────
WITH daily_fraud AS (
    SELECT
        transaction_date,
        ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS daily_fraud_value,
        SUM(is_fraud)                                          AS daily_fraud_count
    FROM vw_fraud_features
    GROUP BY transaction_date
)
SELECT
    transaction_date,
    daily_fraud_value,
    daily_fraud_count,
    ROUND(SUM(daily_fraud_value) OVER (ORDER BY transaction_date ROWS UNBOUNDED PRECEDING), 2) AS cumulative_fraud_value,
    SUM(daily_fraud_count) OVER (ORDER BY transaction_date ROWS UNBOUNDED PRECEDING) AS cumulative_fraud_count
FROM daily_fraud
ORDER BY transaction_date;


-- ─────────────────────────────────────────────────────────────
-- QUERY 12: Multi-factor anomaly detection
--   Flag transactions suspicious on 3+ dimensions
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_id,
    transaction_ts,
    card_number,
    full_name,
    merchant_name,
    category,
    ROUND(amount, 2)                                   AS amount,
    ROUND(amount_z_score, 2)                           AS amount_z_score,
    ROUND(geo_distance_km, 1)                          AS distance_km,
    is_late_night,
    is_far_from_home,
    is_fraud,
    -- Count how many anomaly flags are set
    (CASE WHEN ABS(amount_z_score) > 2 THEN 1 ELSE 0 END
     + is_late_night
     + is_far_from_home
     + CASE WHEN is_weekend = 1 THEN 1 ELSE 0 END
    )                                                  AS anomaly_flag_count
FROM vw_fraud_features
WHERE
    (CASE WHEN ABS(amount_z_score) > 2 THEN 1 ELSE 0 END
     + is_late_night
     + is_far_from_home
     + CASE WHEN is_weekend = 1 THEN 1 ELSE 0 END
    ) >= 3
ORDER BY anomaly_flag_count DESC, amount DESC;
