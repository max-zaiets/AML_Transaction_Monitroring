-- PATTERN 1: Account Drain
-- Account sends out everything it has and hits zero balance.
-- Legit customers rarely do this - usually a sign the account
-- was used specifically to move money and then abandoned.
-- -------------------------------------------------------

CREATE OR REPLACE VIEW vw_account_drain AS
SELECT
    STEP,
    TYPE,
    AMOUNT,
    NAME_ORIG,
    OLD_BALANCE_ORIG,
    NEW_BALANCE_ORIG,
    NAME_DEST,
    IS_FRAUD,
    IS_FLAGGED_FRAUD
FROM RAW_TRANSACTIONS
WHERE OLD_BALANCE_ORIG > 0
  AND NEW_BALANCE_ORIG = 0
  AND AMOUNT = OLD_BALANCE_ORIG
  AND TYPE IN ('TRANSFER', 'CASH_OUT');


-- quick check - how many alerts and what's the fraud rate?
SELECT
    COUNT(*) AS total_alerts,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 2) AS precision_pct
FROM vw_account_drain;



-- PATTERN 2: High-Value CASH_OUT
-- Large cash withdrawals above $200,000.
-- The built-in system flag only watches TRANSFER > 200k -
-- it completely ignores large CASH_OUTs. This rule fills that gap.


CREATE OR REPLACE VIEW vw_high_value_cashout AS
SELECT
  STEP,
  TYPE,
  AMOUNT,
  NAME_ORIG,
  OLD_BALANCE_ORIG,
  NEW_BALANCE_ORIG,
  NAME_DEST,
  IS_FRAUD,
  IS_FLAGGED_FRAUD
FROM RAW_TRANSACTIONS
WHERE TYPE = 'CASH_OUT'
  AND AMOUNT > 200000;

--again, just a view check before we proceed
SELECT
    COUNT(*) AS total_alerts,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 2) AS precision_pct,
    ROUND(AVG(AMOUNT), 2) AS avg_cashout_amount
FROM vw_high_value_cashout;


-- Combined view - all suspicious transactions in one place

CREATE OR REPLACE VIEW vw_suspicious_transactions AS

SELECT
    STEP, TYPE, AMOUNT, NAME_ORIG, NAME_DEST,
    IS_FRAUD, IS_FLAGGED_FRAUD,
    'Account Drain' AS detection_rule
FROM vw_account_drain

UNION ALL

SELECT
    STEP, TYPE, AMOUNT, NAME_ORIG, NAME_DEST,
    IS_FRAUD, IS_FLAGGED_FRAUD,
    'High-Value CASH_OUT' AS detection_rule
FROM vw_high_value_cashout;


-- summary by rule
SELECT
    detection_rule,
    COUNT(*) AS total_alerts,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 2) AS precision_pct,
    ROUND(SUM(AMOUNT), 0) AS total_amount_flagged
FROM vw_suspicious_transactions
GROUP BY detection_rule;


-- Rule comparison - precision and recall for all four rules


CREATE OR REPLACE VIEW vw_rule_comparison AS
SELECT rule_name, total_alerts, confirmed_fraud_caught, precision_pct, recall_pct FROM (

    SELECT 'Existing Flag' AS rule_name,
        SUM(IS_FLAGGED_FRAUD) AS total_alerts,
        SUM(CASE WHEN IS_FRAUD=1 AND IS_FLAGGED_FRAUD=1 THEN 1 ELSE 0 END) AS confirmed_fraud_caught,
        ROUND(SUM(CASE WHEN IS_FRAUD=1 AND IS_FLAGGED_FRAUD=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(IS_FLAGGED_FRAUD),0)*100,2) AS precision_pct,
        ROUND(SUM(CASE WHEN IS_FRAUD=1 AND IS_FLAGGED_FRAUD=1 THEN 1.0 ELSE 0 END)/NULLIF(SUM(IS_FRAUD),0)*100,2) AS recall_pct
    FROM RAW_TRANSACTIONS

    UNION ALL

    SELECT 'Rule A: Exact Balance Transfer',
        COUNT(*), SUM(IS_FRAUD),
        ROUND(SUM(IS_FRAUD)/COUNT(*)*100,2),
        ROUND(SUM(IS_FRAUD)/(SELECT SUM(IS_FRAUD) FROM RAW_TRANSACTIONS)*100,2)
    FROM RAW_TRANSACTIONS
    WHERE TYPE IN ('TRANSFER','CASH_OUT') AND AMOUNT=OLD_BALANCE_ORIG AND NEW_BALANCE_ORIG=0 AND OLD_BALANCE_ORIG>0

    UNION ALL

    SELECT 'Rule B: Destination Mismatch',
        COUNT(*), SUM(IS_FRAUD),
        ROUND(SUM(IS_FRAUD)/COUNT(*)*100,2),
        ROUND(SUM(IS_FRAUD)/(SELECT SUM(IS_FRAUD) FROM RAW_TRANSACTIONS)*100,2)
    FROM RAW_TRANSACTIONS
    WHERE TYPE='TRANSFER' AND OLD_BALANCE_DEST=0 AND NEW_BALANCE_DEST=0 AND AMOUNT>0

    UNION ALL

    SELECT 'Rule C: Combined',
        COUNT(*), SUM(IS_FRAUD),
        ROUND(SUM(IS_FRAUD)/COUNT(*)*100,2),
        ROUND(SUM(IS_FRAUD)/(SELECT SUM(IS_FRAUD) FROM RAW_TRANSACTIONS)*100,2)
    FROM RAW_TRANSACTIONS
    WHERE TYPE IN ('TRANSFER','CASH_OUT') AND AMOUNT=OLD_BALANCE_ORIG AND NEW_BALANCE_ORIG=0
      AND OLD_BALANCE_DEST=0 AND NEW_BALANCE_DEST=0

) results
ORDER BY recall_pct DESC;

-- Fraud timeline - hourly step with daily grouping
-- used for cumulative and daily fraud charts in Power BI


CREATE OR REPLACE VIEW vw_fraud_timeline AS
SELECT
    STEP,
    CAST(CEIL(STEP / 24.0) AS INT)         AS day_number,
    COUNT(*)                                AS tx_count,
    SUM(IS_FRAUD)                           AS fraud_count,
    SUM(SUM(IS_FRAUD)) OVER (ORDER BY STEP) AS cumulative_fraud
FROM RAW_TRANSACTIONS
GROUP BY STEP
ORDER BY STEP;
