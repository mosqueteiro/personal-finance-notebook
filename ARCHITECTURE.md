# Architecture

## Overview

Personal Finance Notebook is a single-user, local-first application built as a Marimo notebook backed by a DuckDB database. There is no server, no API, and no multi-user state — the notebook reads from and writes to a local `finance.db` file.

```
┌─────────────────────────────────────────────────────────────┐
│  Marimo Notebook                                            │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐  │
│  │ Glance Header │ │ Filtered      │ │ Budget Pacing     │  │
│  │ (liquidity +  │ │ Ledger        │ │ (total + category)│  │
│  │  low balance) │ │               │ │                   │  │
│  └───────────────┘ └───────────────┘ └───────────────────┘  │
│  UI cells, helper functions, SQL queries, and rules all     │
│  live together in a single notebook.                        │
└───────────────────────┬─────────────────────────────────────┘
                        │  DuckDB Python API
┌───────────────────────▼─────────────────────────────────────┐
│  Persistence — DuckDB  ────  finance.db                     │
│  (single-user, local file)                                  │
└─────────────────────────────────────────────────────────────┘
```

## Structure

The project starts as a **single Marimo notebook**. UI cells, helper functions, SQL queries, and categorization rules all live together in that one notebook — there is no separate "domain layer" of Python modules. The only thing outside the notebook is the DuckDB file (`finance.db`).

This keeps everything in one place, easy to scan and evolve. If the notebook grows unwieldy, the escape hatch is to extract functions or SQL into Python modules alongside the notebook and import them back — but we cross that bridge only when we reach it.

### Persistence — DuckDB
All state lives in `finance.db`. Tables mirror the entities in the Allium spec (see below). No ORM is planned; the notebook issues SQL directly through DuckDB's Python API.

## Data model

The source of truth for the domain model is `specs/personal-finance-notebook.allium`. Entities:

| Entity             | Purpose                                                    |
|--------------------|------------------------------------------------------------|
| `Account`          | Bank/credit-card account with `low_balance_threshold`.     |
| `AccountStatement` | Uploaded file (CSV/PDF) with a status lifecycle.           |
| `Transaction`      | A single ledger entry linked to an account (and optional statement). |
| `Category`         | Spending category.                                         |
| `CategorizationRule` | `merchant_keyword → target_category` mapping.            |
| `Budget`           | Target amount for a category (or overall) over a period.  |

Status lifecycles (from the spec):

```
AccountStatement:  uploaded ─▶ extracted ─▶ confirmed | rejected
Transaction:       pending_confirmation ─▶ confirmed | rejected
```

## Key flows

### Ingestion & extraction
1. User uploads a CSV/PDF statement (`DataIngestion.upload_statement`) → `AccountStatement` created with status `uploaded`.
2. Extraction creates `Transaction`s in `pending_confirmation`.
3. User confirms or rejects the statement; all its transactions move to the matching status.

### Auto-categorization
On `Transaction.created`, the categorizer matches the merchant against `CategorizationRule.merchant_keyword` and assigns a `Category`. Users can reapply rules on demand (`CategorizationManagement.reapply_rules`).

### Budget pacing (the "5-minute weekly status check")
Read-only query over confirmed transactions in an arbitrary `[start_date, end_date]` window, joined against `Budget`. Returns total spend, per-category spend vs. budget, and low-balance account alerts.

## Decisions & constraints

- **Marimo over Streamlit/Jupyter** — reactive, script-like notebooks that double as an interactive app and are easy to version-control.
- **DuckDB over SQLite/Postgres** — analytical SQL on a local file with zero ops. Single-user by design.
- **Keyword rules over ML** — v1 uses simple `merchant_keyword` matching (transparent, auditable). ML auto-categorization is explicitly deferred to v2.
- **No external integrations** — Plaid, real-time price feeds, and multi-user auth are out of scope for v1. All ingestion is file-based.
- **uv + devenv** — reproducible Python deps and a reproducible system environment, both pinned via lockfiles (`uv.lock`, `devenv.lock`).

## Spec ↔ code alignment

The Allium spec is the behavioural source of truth. When implementation diverges from the spec, prefer one of:
1. Update the implementation to match the spec, or
2. Update the spec (and this document) to reflect an intentional change.

Do not let them drift silently.
