# Information Product Canvas: Personal Finance Notebook

## Phase 1: The Essentials (Discovery)

### 1. Business Questions
* **Account Liquidity:** What are my current account balances, and are any below a "low balance" threshold?
* **Budget Pacing:** How much of my total and category budgets remains for the rest of the month?
* **Subscription Management:** What are my active recurring subscriptions and when is the next charge?
* **Savings Progress:** What is the status of my current savings goals and the required monthly amount to hit them?

### 2. Actions & Outcomes
* **Avoid Fees:** Transfer funds between accounts to prevent overdrafts.
* **Stay Motivated:** Visualize goal growth to maintain consistent saving habits.
* **Audit/Security:** Identify unexpected charges or "zombie" subscriptions to trim waste or catch fraud.
* **Optimization:** Use spending trends to refine future budget allocations.

### 3. Personas
* **The Efficient Family CFO:** A busy father and professional who needs a 5-minute weekly status pulse but also requires a foundation for long-term future planning.

### 4. Vision Statement
For the **Efficient Family CFO** who needs household stability and long-term wealth without losing family time, the **Personal Finance Notebook** is a Marimo-based "Family Wealth Cockpit" that provides automated status checks and interactive "what-if" planning, unlike rigid banking apps or manual spreadsheets.

---

## Phase 2: Delivery Specifics (Design)

### 5. Delivery Types
* **Marimo Notebook:** Local interactive Python environment with reactive UI elements.

### 6. Data Sync
* **Trigger-based:** Updates on demand via file upload (CSV/PDF). State is persisted between sessions using a DuckDB backend.

### 7. Core Business Events
* **Income:** Paydays (Bi-weekly/Monthly).
* **Fixed Outflow:** Mortgage/Rent, Utilities, and identified Subscriptions.
* **Information Ritual:** The "5-Minute Weekly Status Check."

### 8. Feature Stories
* **MVP (v1.0):**
    * *Glance Header:* Top-level liquidity and "Low Balance" alerts.
    * *Auto-Categorizer:* Logic to group transactions from multiple files.
    * *Filtered Ledger:* Ability to filter transactions by account, merchant, and category.
* **Future (v2.0):**
    * *Goal Sliders:* Interactive forecasting for savings/investment performance.
    * *The Kill List:* Automated identification of recurring subscription charges.

---

## Phase 3: Scoping & Sizing

### 9. Will / Won't
* **Will:** Multi-format ingestion (CSV/PDF), DuckDB persistence, basic automated categorization, single-user local state.
* **Won't:** Direct API connections (Plaid), real-time stock/crypto price scraping, multi-user authentication.

### 10. Product Owner
* **Sole Owner:** The User (You).

### 11. T-Shirt Size
* **Large (L):** Due to the complexity of parsing various PDF formats and implementing a persistent SQL (DuckDB) backend.

### 12. Data Sources
* **Local Files:** Bank/Credit Card CSVs and PDF statements.
* **State Storage:** `finance.db` (DuckDB).
