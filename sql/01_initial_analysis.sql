-- quick look at what we're working with
SELECT * FROM RAW_TRANSACTIONS LIMIT 10;

SELECT COUNT(*) AS total_rows FROM RAW_TRANSACTIONS;


-- breakdown by transaction type
SELECT
    TYPE,
    COUNT(*) AS transaction_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total,
    ROUND(AVG(AMOUNT), 2) AS avg_transaction_amount
FROM RAW_TRANSACTIONS
GROUP BY TYPE
ORDER BY transaction_count DESC;


-- checking fraud distribution
-- turns out fraud only appears in TRANSFER and CASH_OUT
SELECT
    TYPE,
    SUM(IS_FRAUD) AS fraud_count,
    COUNT(*) AS total_transactions
FROM RAW_TRANSACTIONS
GROUP BY TYPE
ORDER BY fraud_count DESC;


-- overall fraud rate
SELECT
    COUNT(*) AS total_transactions,
    SUM(IS_FRAUD) AS confirmed_fraud,
    ROUND(SUM(IS_FRAUD) / COUNT(*) * 100, 3) AS fraud_rate_pct
FROM RAW_TRANSACTIONS;


-- how well does the built-in IS_FLAGGED_FRAUD actually work?
SELECT
    IS_FRAUD,
    IS_FLAGGED_FRAUD,
    COUNT(*) AS transaction_count
FROM RAW_TRANSACTIONS
GROUP BY 1, 2
ORDER BY 1 DESC, 2 DESC;

-- the flag is almost useless - it only catches TRANSFER transactions
-- above 200k and misses the vast majority of real fraud


-- precision and recall of the built-in flag
-- precision = of everything it flagged, how much was actually fraud?
-- recall    = of all real fraud, how much did it actually catch?
SELECT
  SUM(CASE WHEN IS_FRAUD = 1 AND IS_FLAGGED_FRAUD = 1 THEN 1 ELSE 0 END) AS true_positive,
  SUM(CASE WHEN IS_FRAUD = 0 AND IS_FLAGGED_FRAUD = 1 THEN 1 ELSE 0 END) AS false_positive,
  SUM(CASE WHEN IS_FRAUD = 1 AND IS_FLAGGED_FRAUD = 0 THEN 1 ELSE 0 END) AS false_negative,
    ROUND(
        SUM(CASE WHEN IS_FRAUD = 1 AND IS_FLAGGED_FRAUD = 1 THEN 1.0 ELSE 0 END)
        / NULLIF(SUM(IS_FLAGGED_FRAUD), 0) * 100, 2
    ) AS precision_pct,
    ROUND(
        SUM(CASE WHEN IS_FRAUD = 1 AND IS_FLAGGED_FRAUD = 1 THEN 1.0 ELSE 0 END)
        / NULLIF(SUM(IS_FRAUD), 0) * 100, 2
    ) AS recall_pct
FROM RAW_TRANSACTIONS;


-- transaction volume over time with cumulative fraud count
-- running total shows exactly when fraud starts spiking
SELECT
    STEP,
    COUNT(*) AS transaction_count,
    SUM(IS_FRAUD) AS fraud_count,
    SUM(SUM(IS_FRAUD)) OVER (ORDER BY STEP) AS cumulative_fraud
FROM RAW_TRANSACTIONS
GROUP BY STEP
ORDER BY STEP;
