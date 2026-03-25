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
  AND TYPE IN ('TRANSFER', 'CASH_OUT');


-- quick check - how many alerts and what's the fraud rate?
SELECT
    COUNT(*) AS total_alerts,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 2) AS precision_pct
FROM vw_account_drain;


-- -------------------------------------------------------
-- PATTERN 2: High-Value CASH_OUT
-- Large cash withdrawals above $200,000.
-- The built-in system flag only watches TRANSFER > 200k -
-- it completely ignores large CASH_OUTs. This rule fills that gap.
-- -------------------------------------------------------

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


-- quick check
SELECT
    COUNT(*) AS total_alerts,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 2) AS precision_pct,
    ROUND(AVG(AMOUNT), 2) AS avg_cashout_amount
FROM vw_high_value_cashout;


-- -------------------------------------------------------
-- Combined view - all suspicious transactions in one place
-- -------------------------------------------------------

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
