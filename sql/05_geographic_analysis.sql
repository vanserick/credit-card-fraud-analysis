-- ============================================================
-- 05_GEOGRAPHIC_ANALYSIS.SQL
-- Dataset: Credit Card Fraud Detection (fraudTest.csv)
-- Purpose: Spatial analysis of fraud by state, city, and geo-distance
-- Depends on: vw_fraud_features (from 02_feature_engineering.sql)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- QUERY 1: Fraud summary by US state
-- ─────────────────────────────────────────────────────────────
SELECT
    state,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(amount), 2)                              AS total_value,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount,
    COUNT(DISTINCT card_number)                        AS unique_cards,
    COUNT(DISTINCT merchant_name)                      AS unique_merchants
FROM vw_fraud_features
GROUP BY state
ORDER BY fraud_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 2: Top 20 cities by fraud count
-- ─────────────────────────────────────────────────────────────
SELECT
    city,
    state,
    city_pop,
    city_tier,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS total_fraud_value
FROM vw_fraud_features
GROUP BY city, state, city_pop, city_tier
ORDER BY fraud_count DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- QUERY 3: Fraud rate by city population tier
-- ─────────────────────────────────────────────────────────────
SELECT
    city_tier,
    COUNT(DISTINCT city)                               AS city_count,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(city_pop), 0)                            AS avg_city_pop,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY city_tier
ORDER BY
    CASE city_tier
        WHEN 'Rural'         THEN 1
        WHEN 'Small Town'    THEN 2
        WHEN 'Mid-size City' THEN 3
        WHEN 'Large City'    THEN 4
        WHEN 'Metro'         THEN 5
    END;


-- ─────────────────────────────────────────────────────────────
-- QUERY 4: Fraud rate by geo-distance band
--   (how far merchant is from cardholder home)
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN geo_distance_km <  10   THEN '0–10 km'
        WHEN geo_distance_km <  25   THEN '10–25 km'
        WHEN geo_distance_km <  50   THEN '25–50 km'
        WHEN geo_distance_km < 100   THEN '50–100 km'
        WHEN geo_distance_km < 250   THEN '100–250 km'
        WHEN geo_distance_km < 500   THEN '250–500 km'
        ELSE '500+ km'
    END                                                AS distance_band,
    COUNT(*)                                           AS total_transactions,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(AVG(geo_distance_km), 1)                     AS avg_distance_km,
    ROUND(AVG(CASE WHEN is_fraud = 1 THEN amount END), 2) AS avg_fraud_amount
FROM vw_fraud_features
GROUP BY 1
ORDER BY MIN(geo_distance_km);


-- ─────────────────────────────────────────────────────────────
-- QUERY 5: Cross-state fraud — customer state vs merchant state
--   (approximate via customer state only; merchant state not in data,
--    but we flag far-from-home as a proxy for cross-geography)
-- ─────────────────────────────────────────────────────────────
SELECT
    state,
    SUM(CASE WHEN is_far_from_home = 0 THEN 1 ELSE 0 END) AS local_txns,
    SUM(CASE WHEN is_far_from_home = 1 THEN 1 ELSE 0 END) AS distant_txns,
    SUM(CASE WHEN is_far_from_home = 1 AND is_fraud = 1 THEN 1 ELSE 0 END) AS distant_fraud,
    ROUND(
        SUM(CASE WHEN is_far_from_home = 1 AND is_fraud = 1 THEN 1 ELSE 0 END) * 100.0
        / NULLIF(SUM(CASE WHEN is_far_from_home = 1 THEN 1 ELSE 0 END), 0), 4
    )                                                  AS distant_fraud_rate_pct,
    ROUND(
        SUM(CASE WHEN is_far_from_home = 0 AND is_fraud = 1 THEN 1 ELSE 0 END) * 100.0
        / NULLIF(SUM(CASE WHEN is_far_from_home = 0 THEN 1 ELSE 0 END), 0), 4
    )                                                  AS local_fraud_rate_pct
FROM vw_fraud_features
GROUP BY state
ORDER BY distant_fraud DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 6: Average geo-distance for fraud vs. legit transactions
-- ─────────────────────────────────────────────────────────────
SELECT
    is_fraud,
    CASE WHEN is_fraud = 1 THEN 'Fraudulent' ELSE 'Legitimate' END AS label,
    COUNT(*)                                           AS txn_count,
    ROUND(AVG(geo_distance_km), 2)                     AS avg_distance_km,
    ROUND(MIN(geo_distance_km), 2)                     AS min_distance_km,
    ROUND(MAX(geo_distance_km), 2)                     AS max_distance_km,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY geo_distance_km), 2) AS median_distance_km,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY geo_distance_km), 2) AS p90_distance_km
FROM vw_fraud_features
GROUP BY is_fraud;


-- ─────────────────────────────────────────────────────────────
-- QUERY 7: State-level fraud heatmap data
--   (State code + fraud rate ready for BI/mapping tools)
-- ─────────────────────────────────────────────────────────────
SELECT
    state                                              AS state_code,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_txns,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_dollar_value,
    COUNT(DISTINCT card_number)                        AS affected_cards,
    -- Normalize fraud rate to 0–100 for heat-map colour scale
    ROUND(
        (SUM(is_fraud) * 100.0 / COUNT(*))
        / MAX(SUM(is_fraud) * 100.0 / COUNT(*)) OVER () * 100, 2
    )                                                  AS fraud_rate_normalized
FROM vw_fraud_features
GROUP BY state
ORDER BY fraud_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 8: Fraud clusters — states with above-average fraud rate
-- ─────────────────────────────────────────────────────────────
WITH state_fraud AS (
    SELECT
        state,
        ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4) AS state_fraud_rate
    FROM vw_fraud_features
    GROUP BY state
),
overall_avg AS (
    SELECT AVG(state_fraud_rate) AS avg_fraud_rate
    FROM state_fraud
)
SELECT
    sf.state,
    sf.state_fraud_rate,
    oa.avg_fraud_rate,
    ROUND(sf.state_fraud_rate - oa.avg_fraud_rate, 4) AS deviation_from_avg,
    CASE
        WHEN sf.state_fraud_rate > oa.avg_fraud_rate * 1.5 THEN 'High-Risk State'
        WHEN sf.state_fraud_rate > oa.avg_fraud_rate       THEN 'Above Average'
        ELSE 'Below Average'
    END                                                AS risk_label
FROM state_fraud sf
CROSS JOIN overall_avg oa
ORDER BY sf.state_fraud_rate DESC;


-- ─────────────────────────────────────────────────────────────
-- QUERY 9: Merchant geo-cluster — merchant location hot spots
--   Bins merchant coordinates into 2-degree lat/long grid cells
-- ─────────────────────────────────────────────────────────────
SELECT
    ROUND(merchant_lat  / 2) * 2                       AS lat_cell,
    ROUND(merchant_long / 2) * 2                       AS long_cell,
    COUNT(*)                                           AS total_txns,
    SUM(is_fraud)                                      AS fraud_count,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 4)        AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amount END), 2) AS fraud_value
FROM vw_fraud_features
GROUP BY lat_cell, long_cell
HAVING COUNT(*) >= 50
ORDER BY fraud_count DESC
LIMIT 30;
