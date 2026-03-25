# 🔍 AML Transaction Monitoring — SQL + Power BI

**Stack:** Snowflake · SQL · Power BI
**Dataset:** PaySim Synthetic Financial Transactions · 3M+ rows
**Domain:** Anti-Money Laundering · Compliance

---

## 🎯 Project Goal

The goal of this project was to evaluate the effectiveness of an existing fraud detection system and build a simple rule-based monitoring layer on top of it. The project simulates full analysis workflow: ingestion of transaction data to Snowflake DWH, exploring it for patterns using only SQL, identifying weaknesses in the current detection logic, and surface high-risk accounts for investigation with further visualisation of our findings.

Two specific objectives:
1. Quantify how much real fraud the existing system actually catches
2. Propose and validate alternative detection rules that fill the gaps

---

## 📂 Dataset

**Source:** [PaySim on Kaggle](https://www.kaggle.com/datasets/ealaxi/paysim1)
**Reference:** Lopez-Rojas, E., Elmir, A., & Axelsson, S. (2016). *PaySim: A financial mobile money simulator for fraud detection.*

PaySim simulates 10 days of mobile money transactions from a real mobile payment service. It includes a ground-truth fraud label (`IS_FRAUD`) and a built-in system detection flag (`IS_FLAGGED_FRAUD`), which made it ideal for evaluating detection performance.

| Column | Description |
|---|---|
| `STEP` | Time unit (1 step = 1 hour) |
| `TYPE` | Transaction type: CASH_IN, CASH_OUT, DEBIT, PAYMENT, TRANSFER |
| `AMOUNT` | Transaction amount (USD) |
| `NAME_ORIG` | Originating account |
| `OLD_BALANCE_ORIG` / `NEW_BALANCE_ORIG` | Sender balance before / after |
| `NAME_DEST` | Destination account |
| `OLD_BALANCE_DEST` / `NEW_BALANCE_DEST` | Receiver balance before / after |
| `IS_FRAUD` | Ground truth fraud label (1 = confirmed fraud) |
| `IS_FLAGGED_FRAUD` | Built-in system flag (triggers only on TRANSFER > $200,000) |

---

## 🛠️ Stack & Setup

- **Snowflake** — data warehouse with custom created DB containing the dataset along with views for PBI visualisation
- **Power BI Desktop** — dashboard connected to Snowflake via native ODBC connector
- **SQL** — all detection logic implemented as Snowflake views

The dataset was loaded directly into Snowflake as table `RAW_TRANSACTIONS`. No external scripts or ETL tools were used.

---

## 🗂️ SQL Structure

| File | Purpose |
|---|---|
| `sql/01_explore.sql` | Exploratory analysis — row counts, type breakdown, fraud distribution, precision & recall of the existing flag |
| `sql/02_detection.sql` | Two AML detection views + consolidated suspicious transactions view |
| `sql/03_risk_scoring.sql` | Account-level risk scoring and tier classification |
| `sql/04_fraud_pattern_analysis.sql` | Rule testing — compares four detection approaches by precision and recall to identify the strongest rule |

### ❄️ Snowflake Views

| View | Description |
|---|---|
| `vw_account_drain` | Accounts fully emptied via TRANSFER or CASH_OUT (amount = full balance) |
| `vw_high_value_cashout` | CASH_OUT transactions above $200,000 |
| `vw_suspicious_transactions` | Union of both detection rules with rule label |
| `vw_account_risk` | Risk score and tier per account (HIGH / MEDIUM) |
| `vw_fraud_timeline` | Hourly aggregation with cumulative fraud for timeline charts |
| `vw_rule_comparison` | Side-by-side precision and recall for all four detection rules |

**Snowflake schema:**

![Snowflake Tables](screenshots/snowflake_tables.png)
![Snowflake Views](screenshots/snowflake_views.png)

---

## 🔎 Exploratory Analysis

The first step was understanding the shape of the data and the baseline performance of the existing system.

**Key findings from exploration:**

- Fraud appears exclusively in two transaction types: **TRANSFER** and **CASH_OUT**. The remaining three types (PAYMENT, CASH_IN, DEBIT) have zero fraud — which immediately narrows the scope of monitoring needed.

- The built-in `IS_FLAGGED_FRAUD` flag only triggers on TRANSFER transactions above $200,000. A precision/recall analysis revealed that out of 2,699 confirmed fraud cases, the system flagged exactly **1**. That is a recall of approximately **0.04%**.

- Fraud is distributed consistently across the entire 10-day simulation period — no single spike, no quiet period. This suggests a systemic and ongoing problem rather than an isolated incident.

---

## ⚙️ Detection Logic

Two rules were implemented as SQL views to detect suspicious behavior missed by the existing system.

**Rule 1 — Account Drain**
Flags accounts where the transaction amount exactly equals the sender's starting balance, leaving zero behind (`AMOUNT = OLD_BALANCE_ORIG` and `NEW_BALANCE_ORIG = 0`). The exact-match condition is critical: fraudsters drain accounts to the penny, while legitimate large transfers almost never consume 100% of the balance. This rule achieves 100% precision and 97.89% recall on the dataset.

**Rule 2 — High-Value CASH_OUT**
Flags CASH_OUT transactions above $200,000. The existing system monitors large TRANSFER transactions but completely ignores large cash withdrawals. This rule directly fills that blind spot.

**📊 Risk Scoring**

Each account is scored based on which rules it triggers:

| Rule | Points |
|---|---|
| Account Drain | 2 |
| High-Value CASH_OUT | 3 |

Accounts are then classified into two tiers:
- 🔴 **HIGH** — score ≥ 3
- 🟠 **MEDIUM** — score = 2

The final query in `03_risk_scoring.sql` cross-checks whether HIGH-tier accounts have a higher confirmed fraud rate than MEDIUM — which validates that the scoring is directionally correct.

---

## 📈 Dashboard — What the Data Shows

The Power BI dashboard tells a five-page story.

**Page 1 — The Detection Gap**
The opening page answers one question directly: how much fraud does the current system actually catch? Out of 2,699 confirmed fraud cases, the system flagged 1. The bar chart makes this gap impossible to miss. This is the core problem the rest of the project responds to.

![Detection Gap](screenshots/pbi1.png)

**Page 2 — Where Fraud Happens**
Fraud is entirely concentrated in CASH_OUT and TRANSFER. The remaining transaction types are clean. This means a compliance team does not need to monitor all 3 million transactions — focusing on two types makes the problem manageable.

![Where Fraud Happens](screenshots/pbi2.png)

**Page 3 — Fraud Over Time**
The cumulative fraud chart shows a steady, continuous rise over the 10-day period — no spikes, no quiet periods. Fraud was happening every single hour. The daily count chart confirms there was no day with zero fraud. This reinforces that the problem requires continuous monitoring, not periodic reviews.

![Fraud Over Time](screenshots/pbi3.png)

**Page 4 — Risk Accounts**
Applying the two detection rules produces a prioritized list of accounts for investigation, classified as HIGH or MEDIUM risk. Instead of reviewing 3 million transactions, a compliance analyst starts from the top of this list.

![Risk Accounts](screenshots/pbi4.png)

**Page 5 — Rule Comparison**
Four detection rules tested side by side: the existing system flag, Rule A (exact balance transfer), Rule B (destination mismatch), and Rule C (combined). The chart shows confirmed fraud caught and recall for each rule. Rule A stands out — 2,642 alerts, all confirmed fraud, recall of 97.89%. Rule C matches the precision but catches only 47.80% of fraud because it requires both conditions simultaneously. This page explains why Rule A was chosen as the foundation for the detection logic.

![Rule Comparison](screenshots/pbi5.png)

---

## 📋 Conclusions

1. **The existing detection system is nearly non-functional.** A recall of 0.04% means 99.96% of real fraud passes through undetected. This is not a minor gap — it is a fundamental limitation of a threshold-only approach.

2. **Fraud is predictable in its location.** It concentrates in just two transaction types. Any monitoring strategy should prioritize CASH_OUT and TRANSFER.

3. **Fraud is continuous, not episodic.** The steady accumulation over 10 days means a one-time audit would miss most of it. Real-time or daily monitoring is necessary.

4. **Simple rules add meaningful value.** Two straightforward SQL rules — account drain and large cash withdrawals — already produce a focused list of suspicious accounts. This demonstrates that even without machine learning, rule-based logic can significantly improve detection coverage over a naive threshold approach.

5. **One condition changes everything.** Initial testing showed the account drain rule generating 593,000 alerts at 0.45% precision — essentially unusable. Adding a single condition (`AMOUNT = OLD_BALANCE_ORIG`) reduced alerts to ~2,600 while raising precision to 100% and recall to 97.89%. The insight: fraudsters transfer exactly their full balance to the penny. Legitimate customers almost never do this.
