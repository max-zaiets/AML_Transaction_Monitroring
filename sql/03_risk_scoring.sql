USE WAREHOUSE COMPUTE_WH;
USE DATABASE AML_PROJECT;
USE SCHEMA COMPLIANCE;


-- per-account risk score based on which rules they trigger
-- account drain = 2pts, high-value cashout = 3pts (larger amounts = higher risk)
-- HIGH >= 3, MEDIUM = 2

CREATE OR REPLACE VIEW vw_account_risk AS
WITH alerts AS (

    SELECT NAME_ORIG AS account, 2 AS risk_points, 'Account Drain' AS rule
    FROM vw_account_drain

    UNION ALL

    SELECT NAME_ORIG AS account, 3 AS risk_points, 'High-Value CASH_OUT' AS rule
    FROM vw_high_value_cashout

),
account_totals AS (

  SELECT
      account,
      SUM(risk_points) AS risk_score,
      COUNT(DISTINCT rule) AS rules_triggered,
      LISTAGG(DISTINCT rule, ', ') AS triggered_rules
  FROM alerts
  GROUP BY account

)
SELECT
    account,
    risk_score,
    rules_triggered,
    triggered_rules,
    CASE
        WHEN risk_score >= 3 THEN 'HIGH'
        ELSE 'MEDIUM'
    END AS risk_tier
FROM account_totals;


-- how many accounts in each tier?
SELECT
    risk_tier,
    COUNT(*) AS account_count,
    ROUND(AVG(risk_score), 2) AS avg_risk_score
FROM vw_account_risk
GROUP BY risk_tier
ORDER BY avg_risk_score DESC;


-- top 20 riskiest accounts
SELECT *
FROM vw_account_risk
ORDER BY risk_score DESC
LIMIT 20;


-- cross-check: do HIGH risk accounts actually correspond to fraud?
-- if the scoring makes sense, HIGH should have a higher fraud rate than MEDIUM
SELECT
    r.risk_tier,
    COUNT(DISTINCT t.NAME_ORIG) AS unique_accounts,
    SUM(t.IS_FRAUD) AS confirmed_fraud_transactions,
    ROUND(SUM(t.IS_FRAUD) / COUNT(*) * 100, 3) AS fraud_rate_pct
FROM RAW_TRANSACTIONS t
JOIN vw_account_risk r ON t.NAME_ORIG = r.account
GROUP BY r.risk_tier
ORDER BY fraud_rate_pct DESC;
