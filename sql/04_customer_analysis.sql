-- ============================================================
-- 04_CUSTOMER_ANALYSIS.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Cardholder-level fraud behavior, profiling, and risk scoring
-- Depends on: vw_fraud_features (from 02_feature_engineering.sql)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- QUERY 1: Customer-level fraud summary
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    gender,
    customer_age,
    city,
    state,
    job,
    city_tier,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_spend,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS total_fraud_amount,
    ROUND(AVG(amount), 2)                              AS avg_transaction_amount,
    MIN(transaction_date)                              AS first_transaction,
    MAX(transaction_date)                              AS last_transaction,
    COUNT(DISTINCT category)                           AS unique_categories,
    COUNT(DISTINCT merchant_name)                      AS unique_merchants
FROM vw_fraud_features
GROUP BY
    card_number, full_name, gender, customer_age,
    city, state, job, city_tier
ORDER BY fraud_count DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 2: Cards with multiple fraud incidents (repeat victims)
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    SUM(is_fraud)                                      AS fraud_incidents,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS total_fraud_loss,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount,
    MIN(CASE WHEN is_fraud = 1 THEN transaction_date END) AS first_fraud_date,
    MAX(CASE WHEN is_fraud = 1 THEN transaction_date END) AS last_fraud_date
FROM vw_fraud_features
GROUP BY card_number, full_name
HAVING SUM(is_fraud) > 1
ORDER BY fraud_incidents DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 3: Customer spending profile by category
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    category,
    COUNT(*)                                           AS txn_count,
    ROUND(SUM(amount), 2)                              AS total_spend,
    ROUND(AVG(amount), 2)                              AS avg_spend,
    SUM(is_fraud)                                      AS fraud_count
FROM vw_fraud_features
GROUP BY card_number, full_name, category
ORDER BY card_number, total_spend DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 4: Fraud rate by job occupation
-- ─────────────────────────────────────────────────────────────
SELECT
    job,
    COUNT(DISTINCT card_number)                        AS unique_customers,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(amount), 2)                              AS avg_transaction_amount,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY job
HAVING COUNT(*) >= 10
ORDER BY fraud_rate_pct DESC
LIMIT 25;


-- ─────────────────────────────────────────────────────────────
-- QUERY 5: Fraud rate by age group and gender (cross-tab)
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN customer_age < 25 THEN 'Under 25'
        WHEN customer_age < 35 THEN '25-34'
        WHEN customer_age < 45 THEN '35-44'
        WHEN customer_age < 55 THEN '45-54'
        WHEN customer_age < 65 THEN '55-64'
        ELSE '65+'
    END                                                AS age_group,
    gender,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY 1, gender
ORDER BY age_group, gender;


-- ─────────────────────────────────────────────────────────────
-- QUERY 6: Customers who transacted late at night (00:00–05:59)
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    COUNT(*)                                           AS late_night_txns,
    SUM(is_fraud)                                      AS late_night_fraud,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)        AS late_night_fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS late_night_total_spend
FROM vw_fraud_features
WHERE is_late_night = 1
GROUP BY card_number, full_name
ORDER BY late_night_fraud DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 7: Customer transaction velocity — high-frequency spenders
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    COUNT(*)                                           AS total_transactions,
    COUNT(*) / NULLIF(
        DATEDIFF('day',
            MIN(transaction_date),
            MAX(transaction_date)
        ), 0
    )                                                  AS avg_txns_per_day,
    ROUND(SUM(amount), 2)                              AS total_spend,
    SUM(is_fraud)                                      AS fraud_count
FROM vw_fraud_features
GROUP BY card_number, full_name
HAVING COUNT(*) > 5
ORDER BY avg_txns_per_day DESC
LIMIT 50;


-- ─────────────────────────────────────────────────────────────
-- QUERY 8: Customer risk score
--   Composite score: fraud history + late-night activity
--   + high z-score amount + far-from-home transactions
-- ─────────────────────────────────────────────────────────────
SELECT
    card_number,
    full_name,
    gender,
    state,
    COUNT(*)                                                       AS total_txns,
    SUM(is_fraud)                                                  AS confirmed_fraud_count,
    -- Component scores (0–25 points each, total max 100)
    LEAST(SUM(is_fraud)            * 10, 25)                      AS score_fraud_history,
    LEAST(SUM(is_late_night)       * 2,  25)                      AS score_late_night,
    LEAST(SUM(is_far_from_home)    * 3,  25)                      AS score_geo_anomaly,
    LEAST(SUM(CASE WHEN ABS(amount_z_score) > 2 THEN 1 ELSE 0 END) * 3, 25) AS score_amount_anomaly,
    -- Total composite risk score
    LEAST(SUM(is_fraud) * 10, 25)
    + LEAST(SUM(is_late_night) * 2, 25)
    + LEAST(SUM(is_far_from_home) * 3, 25)
    + LEAST(SUM(CASE WHEN ABS(amount_z_score) > 2 THEN 1 ELSE 0 END) * 3, 25) AS risk_score,
    -- Risk tier
    CASE
        WHEN LEAST(SUM(is_fraud)*10,25) + LEAST(SUM(is_late_night)*2,25)
           + LEAST(SUM(is_far_from_home)*3,25)
           + LEAST(SUM(CASE WHEN ABS(amount_z_score)>2 THEN 1 ELSE 0 END)*3,25) >= 50 THEN 'High Risk'
        WHEN LEAST(SUM(is_fraud)*10,25) + LEAST(SUM(is_late_night)*2,25)
           + LEAST(SUM(is_far_from_home)*3,25)
           + LEAST(SUM(CASE WHEN ABS(amount_z_score)>2 THEN 1 ELSE 0 END)*3,25) >= 25 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END                                                            AS risk_tier
FROM vw_fraud_features
GROUP BY card_number, full_name, gender, state
ORDER BY risk_score DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 9: New vs returning customers — fraud comparison
--   "New" = first transaction observed in the dataset
-- ─────────────────────────────────────────────────────────────
WITH first_txn AS (
    SELECT
        card_number,
        MIN(transaction_ts) AS first_seen_ts
    FROM vw_fraud_features
    GROUP BY card_number
)
SELECT
    CASE
        WHEN f.transaction_ts = ft.first_seen_ts THEN 'First Transaction'
        ELSE 'Returning Customer'
    END                                                AS customer_type,
    COUNT(*)                                           AS total_txns,
    SUM(f.is_fraud)                                    AS fraud_count,
    ROUND(SUM(f.is_fraud) * 100.0 / COUNT(*), 4)      AS fraud_rate_pct,
    ROUND(AVG(f.amount), 2)                            AS avg_amount
FROM vw_fraud_features f
JOIN first_txn ft ON ft.card_number = f.card_number
GROUP BY 1;
