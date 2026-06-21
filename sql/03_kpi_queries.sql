-- ============================================================
-- 03_KPI_QUERIES.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Top-level business KPIs for fraud monitoring dashboards
-- Depends on: vw_fraud_features (from 02_feature_engineering.sql)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- KPI 1: Overall fraud summary
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS total_fraud_cases,
    COUNT(*) - SUM(is_fraud)                          AS total_legit_cases,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_transaction_value,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS total_fraud_value,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END)
          * 100.0 / SUM(amount), 4)                   AS fraud_value_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount,
    ROUND(AVG(CASE WHEN is_fraud = 0 THEN amount END), 2) AS avg_legit_amount
FROM vw_fraud_features;


-- ─────────────────────────────────────────────────────────────
-- KPI 2: Fraud rate by merchant category
-- ─────────────────────────────────────────────────────────────
SELECT
    category,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_value,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY category
ORDER BY fraud_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- KPI 3: Monthly fraud trend
-- ─────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC('month', transaction_date)              AS month,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value
FROM vw_fraud_features
GROUP BY DATE_TRUNC('month', transaction_date)
ORDER BY month;


-- ─────────────────────────────────────────────────────────────
-- KPI 4: Fraud rate by hour of day (heatmap input)
-- ─────────────────────────────────────────────────────────────
SELECT
    transaction_hour,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY transaction_hour
ORDER BY transaction_hour;


-- ─────────────────────────────────────────────────────────────
-- KPI 5: Fraud rate — weekday vs weekend
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE WHEN is_weekend = 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(amount), 2)                              AS avg_transaction_amount
FROM vw_fraud_features
GROUP BY is_weekend;


-- ─────────────────────────────────────────────────────────────
-- KPI 6: Fraud rate by gender
-- ─────────────────────────────────────────────────────────────
SELECT
    gender,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount,
    ROUND(AVG(CASE WHEN is_fraud = 0 THEN amount END), 2) AS avg_legit_amount
FROM vw_fraud_features
GROUP BY gender;


-- ─────────────────────────────────────────────────────────────
-- KPI 7: Fraud rate by customer age group
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
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY 1
ORDER BY MIN(customer_age);


-- ─────────────────────────────────────────────────────────────
-- KPI 8: Fraud rate by city population tier
-- ─────────────────────────────────────────────────────────────
SELECT
    city_tier,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY city_tier
ORDER BY fraud_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- KPI 9: Transactions and fraud flagged as "far from home"
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE WHEN is_far_from_home = 1 THEN 'Far (>100 km)' ELSE 'Near (≤100 km)' END AS distance_group,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct
FROM vw_fraud_features
GROUP BY is_far_from_home;


-- ─────────────────────────────────────────────────────────────
-- KPI 10: Top 10 highest-fraud-value merchants
-- ─────────────────────────────────────────────────────────────
SELECT
    merchant_name,
    category,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS total_fraud_value,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM vw_fraud_features
GROUP BY merchant_name, category
ORDER BY total_fraud_value DESC
LIMIT 10;
