# Data Model

This document defines the persistence model for the Personal Finance Notebook at
three levels: conceptual, logical, and physical. The behavioural contract is the
source of truth in `specs/personal-finance-notebook.allium`; this document maps
that contract to DuckDB without introducing a separate ORM or service layer.

## Scope and Decisions

The model supports the v1 MVP:

- Single-user, local-only state in `finance.db`.
- USD monetary values only. There is no currency column.
- File-based CSV and PDF statement ingestion.
- Keyword categorization, confirmed transaction ledgers, and budget pacing.
- No bank API, market-price, authentication, or multi-user data model.

The following decisions apply to the physical model:

| Concern | Decision |
|---|---|
| Table names | Plural `snake_case`; `transactions` avoids the reserved-word ambiguity of `transaction`. |
| Primary keys | `INTEGER` surrogate keys generated from one DuckDB sequence per table. |
| Money | `DECIMAL(18,2)` with a two-decimal USD rounding boundary. |
| Transaction amounts | Positive magnitudes; `income` adds to balance and `expense` subtracts from balance. |
| Status fields | `VARCHAR` with `CHECK` constraints; legal transitions are enforced by notebook mutations. |
| Derived account values | A read-only view, not stored columns or generated columns. |
| Deletes | Restrictive foreign keys and lifecycle statuses; no cascading deletes. |
| Schema bootstrap | Idempotent DDL executed when the notebook opens the database. Migrations are deferred until schema evolution requires them. |

## Conceptual Model

### Entities

| Entity | Purpose | Attributes |
|---|---|---|
| `Account` | A bank or credit-card account whose liquidity is tracked. | `name`, `institution`, `status`, `starting_balance`, `low_balance_threshold`, `created_at` |
| `AccountStatement` | An uploaded CSV/PDF file and its extraction and confirmation state. | `account`, `file_name`, `format`, `status`, `uploaded_at`, `start_date`, `end_date`, `content_hash`, `ending_balance` |
| `Transaction` | A ledger entry belonging to an account and optionally a statement. | `account`, `statement`, `status`, `date`, `amount`, `type`, `merchant`, `description`, `category`, `manually_categorized`, `created_at` |
| `Category` | A label used to classify transactions. | `name`, `created_at` |
| `CategorizationRule` | A merchant keyword to category mapping. | `merchant_keyword`, `target_category`, `created_at` |
| `Budget` | A monthly or yearly spending target, either overall or for one category. | `name`, `target_category`, `amount`, `period`, `created_at` |

`current_balance` and `is_low_balance` are derived properties of `Account`:

```text
current_balance = starting_balance
                 + sum(confirmed income amounts)
                 - sum(confirmed expense amounts)

is_low_balance = current_balance < low_balance_threshold
```

The `starting_balance` is the baseline before the confirmed transactions used
in the calculation. The current specification does not include an effective
date for that baseline; the implementation must therefore preserve that
assumption consistently.

### Relationships

| Relationship | Cardinality | Meaning |
|---|---:|---|
| `Account` to `AccountStatement` | 1 to many | An account can have many uploaded statements; every statement belongs to one account. |
| `Account` to `Transaction` | 1 to many | An account can have many transactions; every transaction belongs to one account. |
| `AccountStatement` to `Transaction` | 1 to many, optional on transaction | Extraction creates zero or more transactions for a statement. A transaction may also be created without a statement. |
| `Category` to `Transaction` | 1 to many, optional on transaction | A transaction may be uncategorized while being processed; the fallback category is `Uncategorized`. |
| `Category` to `CategorizationRule` | 1 to many | Many merchant keywords can target one category. Every rule targets one category. |
| `Category` to `Budget` | 1 to many, optional on budget | A budget with no target category is an overall budget; otherwise it applies only to its target category. |

There are no many-to-many relationships in v1, so no bridge tables are needed.
The account reference on both `AccountStatement` and `Transaction` is
intentional: it supports direct account queries and preserves the invariant
that a transaction's statement, when present, belongs to the same account.

### Business Rules That Shape the Model

| Rule | Data-model consequence |
|---|---|
| Statement deduplication | Store the uploaded file's content hash and enforce uniqueness for an account/hash pair when the hash is present. |
| Statement extraction | Extracted transactions start as `pending_confirmation` and retain their statement provenance. |
| Statement confirmation or rejection | A statement transition cascades the corresponding status to its pending transactions. This is domain logic, not a database `ON DELETE` cascade. |
| Balance derivation | Only `confirmed` transactions contribute to account balance. Rejected and pending transactions do not. |
| Auto-categorization | A transaction can initially have a null category, then receives a category from the case-insensitive substring rules. |
| Manual categorization | A manual category edit sets `manually_categorized` to true; reapplication must not overwrite it. |
| Budget pacing | Pacing queries use confirmed expense transactions in the current calendar month or year. An overall budget rolls up all categories; a category budget filters to its target category. |
| Account closure | Closing an account changes lifecycle status. It does not remove its historical statements or transactions. |

## Logical Model

### Naming and Keys

Entity names remain singular in the domain model. Physical tables and indexes
use plural `snake_case` names. Every table has an immutable `id` column with an
`INTEGER` surrogate key. The key is generated by a table-specific DuckDB
sequence such as `seq_accounts`.

Surrogate keys are preferred over natural keys because names, file paths,
merchant strings, and statement contents can change or repeat. They are also
compact, sequential, and easy to inspect in a single-user local database.

### Attribute Constraints

The `?` suffix in the Allium specification maps to a nullable SQL column. All
other entity attributes are required unless a physical constraint below says
otherwise.

#### `accounts`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `name` | String | Required and non-empty. |
| `institution` | String | Required and non-empty. |
| `status` | Account status | Required; `active` or `closed`. |
| `starting_balance` | USD amount | Required. Negative balances are permitted to represent an overdraft baseline. |
| `low_balance_threshold` | USD amount | Required. The low-balance comparison is strict: current balance below the threshold is low. |
| `created_at` | Timestamp | Required. |

#### `account_statements`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `account_id` | Account key | Required foreign key to `accounts`. |
| `file_name` | String | Required and non-empty. The upload rule currently supplies the provided file path. |
| `format` | Statement format | Required; `csv` or `pdf`. |
| `status` | Statement status | Required; `uploaded`, `extracted`, `confirmed`, or `rejected`. |
| `uploaded_at` | Timestamp | Required. This is the statement's creation/audit timestamp. |
| `start_date` | Timestamp | Optional. |
| `end_date` | Timestamp | Optional. When both dates exist, it must not precede `start_date`. |
| `content_hash` | String | Optional in the logical contract; upload handling should populate it. Uniqueness applies to non-null account/hash pairs. |
| `ending_balance` | USD amount | Optional parsed statement balance. It is persisted input, not a derived account balance. |

#### `transactions`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `account_id` | Account key | Required foreign key to `accounts`. |
| `statement_id` | Statement key | Optional foreign key to `account_statements`. When present, it must reference a statement for the same account. |
| `status` | Transaction status | Required; `pending_confirmation`, `confirmed`, or `rejected`. |
| `date` | Timestamp | Required. |
| `amount` | USD amount | Required and non-negative. It is stored as a positive magnitude. |
| `type` | Transaction type | Required; `income` or `expense`. |
| `merchant` | String | Required and non-empty. |
| `description` | String | Optional. |
| `category_id` | Category key | Optional foreign key to `categories`. |
| `manually_categorized` | Boolean | Required. It defaults to false in application creation logic and may only be true when `category_id` is non-null. |
| `created_at` | Timestamp | Required. |

#### `categories`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `name` | String | Required, non-empty, and unique. The seeded `Uncategorized` row is the categorization fallback. |
| `created_at` | Timestamp | Required. |

#### `categorization_rules`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `merchant_keyword` | String | Required and non-empty after trimming. Matching is case-insensitive substring matching. |
| `target_category_id` | Category key | Required foreign key to `categories`. |
| `created_at` | Timestamp | Required. |

The matching rule chooses the longest matching keyword. Equal-length matches
are not resolved by the current behavioural specification, so the categorizer
must not rely on physical row order for that case.

#### `budgets`

| Column | Logical type | Nullability and constraints |
|---|---|---|
| `id` | Integer key | Required, primary key. |
| `name` | String | Required and non-empty. |
| `target_category_id` | Category key | Optional foreign key to `categories`; null means overall budget. |
| `amount` | USD amount | Required and non-negative. |
| `period` | Budget period | Required; `monthly` or `yearly`. |
| `created_at` | Timestamp | Required. |

V1 permits at most one budget for each category/period scope and at most one
overall budget for each period. A normal SQL unique constraint handles the
category-targeted case. Because SQL unique constraints generally allow
multiple nulls, the notebook mutation path must explicitly reject a second
overall budget for the same period.

### Status Lifecycles

The database constrains status values but does not encode transitions. Notebook
mutation functions must check the current status and perform the transition in
the same transaction as any cascading child updates.

```text
Account:
  active <-> closed

AccountStatement:
  uploaded -> extracted -> confirmed
                       -> rejected

Transaction:
  pending_confirmation -> confirmed
                        -> rejected
```

Terminal statuses are `confirmed` and `rejected` for statements and
transactions. Account status is reversible and has no terminal state.

### Derived and Audit Data

`current_balance` and `is_low_balance` are not stored on `accounts` because
they depend on rows in `transactions`. They are exposed by the
`account_balances` view described below. Budget pacing is also query-derived;
the database does not store a current-period snapshot.

The model stores `created_at` for entities that have it in the specification.
`uploaded_at` is the creation/audit timestamp for a statement. V1 does not add
`updated_at`, status history, or reconciliation history because those are not
part of the behavioural contract.

### Referential Integrity and Retention

Foreign keys are restrictive by default:

- An account cannot be removed while statements or transactions reference it.
- A statement cannot be removed while extracted transactions reference it.
- A category cannot be removed while transactions, rules, or budgets reference it.
- A transaction is retained and moves to `rejected` rather than being deleted.
- Account closure is the retention-safe alternative to deleting an account.

IDs are immutable, so no `ON UPDATE` behavior is needed. The notebook should
avoid hard-delete controls unless the specification adds explicit deletion
semantics.

## Physical Model: DuckDB

### Types

| Domain value | DuckDB type | Rationale |
|---|---|---|
| Surrogate key | `INTEGER` | Compact sequential key for the local single-user database. |
| Currency amount | `DECIMAL(18,2)` | Exact two-decimal USD arithmetic with ample whole-number range. |
| Timestamp | `TIMESTAMP` | Matches the specification's `Timestamp`; the notebook treats statement and transaction times as local calendar values. |
| String | `VARCHAR` | File metadata, merchant text, descriptions, and names. |
| Boolean | `BOOLEAN` | Manual categorization flag and derived low-balance result. |
| Enum/status | `VARCHAR` plus `CHECK` | More evolvable than native DuckDB enums while retaining database validation. |

The application must round monetary inputs to two decimal places before writes.
Balance and pacing calculations must use `DECIMAL` expressions and should not
convert money to binary floating point.

### Bootstrap DDL

The following is the schema contract. It is deliberately idempotent so it can
run from a notebook-startup cell against an existing `finance.db`. `IF NOT
EXISTS` does not migrate an already-created table; structural changes require a
future migration strategy.

```sql
CREATE SEQUENCE IF NOT EXISTS seq_accounts START 1;
CREATE SEQUENCE IF NOT EXISTS seq_account_statements START 1;
CREATE SEQUENCE IF NOT EXISTS seq_transactions START 1;
CREATE SEQUENCE IF NOT EXISTS seq_categories START 1;
CREATE SEQUENCE IF NOT EXISTS seq_categorization_rules START 1;
CREATE SEQUENCE IF NOT EXISTS seq_budgets START 1;

CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_categories'),
    name VARCHAR NOT NULL,
    created_at TIMESTAMP NOT NULL,
    UNIQUE (name),
    CHECK (length(trim(name)) > 0)
);

CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_accounts'),
    name VARCHAR NOT NULL,
    institution VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    starting_balance DECIMAL(18, 2) NOT NULL,
    low_balance_threshold DECIMAL(18, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    CHECK (length(trim(name)) > 0),
    CHECK (length(trim(institution)) > 0),
    CHECK (status IN ('active', 'closed'))
);

CREATE TABLE IF NOT EXISTS account_statements (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_account_statements'),
    account_id INTEGER NOT NULL,
    file_name VARCHAR NOT NULL,
    format VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    uploaded_at TIMESTAMP NOT NULL,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    content_hash VARCHAR,
    ending_balance DECIMAL(18, 2),
    UNIQUE (id, account_id),
    UNIQUE (account_id, content_hash),
    CHECK (length(trim(file_name)) > 0),
    CHECK (format IN ('csv', 'pdf')),
    CHECK (status IN ('uploaded', 'extracted', 'confirmed', 'rejected')),
    CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date),
    FOREIGN KEY (account_id) REFERENCES accounts (id)
);

CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_transactions'),
    account_id INTEGER NOT NULL,
    statement_id INTEGER,
    status VARCHAR NOT NULL,
    date TIMESTAMP NOT NULL,
    amount DECIMAL(18, 2) NOT NULL,
    type VARCHAR NOT NULL,
    merchant VARCHAR NOT NULL,
    description VARCHAR,
    category_id INTEGER,
    manually_categorized BOOLEAN NOT NULL,
    created_at TIMESTAMP NOT NULL,
    CHECK (status IN ('pending_confirmation', 'confirmed', 'rejected')),
    CHECK (amount >= 0),
    CHECK (type IN ('income', 'expense')),
    CHECK (length(trim(merchant)) > 0),
    CHECK (NOT manually_categorized OR category_id IS NOT NULL),
    FOREIGN KEY (account_id) REFERENCES accounts (id),
    FOREIGN KEY (statement_id, account_id)
        REFERENCES account_statements (id, account_id),
    FOREIGN KEY (category_id) REFERENCES categories (id)
);

CREATE TABLE IF NOT EXISTS categorization_rules (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_categorization_rules'),
    merchant_keyword VARCHAR NOT NULL,
    target_category_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    CHECK (length(trim(merchant_keyword)) > 0),
    FOREIGN KEY (target_category_id) REFERENCES categories (id)
);

CREATE TABLE IF NOT EXISTS budgets (
    id INTEGER PRIMARY KEY DEFAULT nextval('seq_budgets'),
    name VARCHAR NOT NULL,
    target_category_id INTEGER,
    amount DECIMAL(18, 2) NOT NULL,
    period VARCHAR NOT NULL,
    created_at TIMESTAMP NOT NULL,
    UNIQUE (period, target_category_id),
    CHECK (length(trim(name)) > 0),
    CHECK (amount >= 0),
    CHECK (period IN ('monthly', 'yearly')),
    FOREIGN KEY (target_category_id) REFERENCES categories (id)
);

CREATE INDEX IF NOT EXISTS idx_transactions_account_status_date
    ON transactions (account_id, status, date);

CREATE INDEX IF NOT EXISTS idx_transactions_category_status_date
    ON transactions (category_id, status, date);

CREATE INDEX IF NOT EXISTS idx_transactions_status_date
    ON transactions (status, date);

CREATE INDEX IF NOT EXISTS idx_account_statements_account_status_uploaded
    ON account_statements (account_id, status, uploaded_at);
```

The composite unique key on `account_statements (id, account_id)` exists to
support the composite transaction foreign key. That foreign key prevents a
transaction from linking to a statement belonging to another account.

The `(account_id, content_hash)` unique constraint deduplicates non-null
content hashes. The upload rule is responsible for computing and supplying a
hash; the nullable column remains compatible with the logical specification and
allows records created by future/manual workflows that do not have a hash.

### Derived Account View

The account view is recreated after the base tables exist. It is the read model
used by the Glance Header and low-balance alerts.

```sql
CREATE OR REPLACE VIEW account_balances AS
WITH confirmed_net AS (
    SELECT
        account_id,
        SUM(
            CASE
                WHEN type = 'income' THEN amount
                WHEN type = 'expense' THEN -amount
            END
        ) AS net_balance
    FROM transactions
    WHERE status = 'confirmed'
    GROUP BY account_id
), account_values AS (
    SELECT
        a.id,
        a.name,
        a.institution,
        a.status,
        a.starting_balance,
        a.low_balance_threshold,
        a.created_at,
        a.starting_balance
            + COALESCE(cn.net_balance, CAST(0 AS DECIMAL(18, 2)))
            AS current_balance
    FROM accounts AS a
    LEFT JOIN confirmed_net AS cn ON cn.account_id = a.id
)
SELECT
    id,
    name,
    institution,
    status,
    starting_balance,
    low_balance_threshold,
    created_at,
    current_balance,
    current_balance < low_balance_threshold AS is_low_balance
FROM account_values;
```

Budget pacing remains a parameterized query over `transactions` and
`budgets`. It must select the current calendar month for `monthly` budgets and
the current calendar year for `yearly` budgets, filter transactions to
`status = 'confirmed'` and `type = 'expense'`, and apply category filtering
only when `target_category_id` is non-null.

### Seed Data

The bootstrap cell must ensure that the fallback category exists without
creating duplicates:

```sql
INSERT INTO categories (name, created_at)
SELECT 'Uncategorized', CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM categories WHERE name = 'Uncategorized'
);
```

### Bootstrap Execution

The notebook should open one DuckDB connection, execute the sequences and
tables in dependency order, create the view and indexes, then seed
`Uncategorized`. The operation should run in a transaction where DuckDB allows
it, rolling back on failure. Schema changes should not be hidden inside normal
CRUD cells.

An explicit migrations directory is not needed for the initial notebook. If a
released database needs a structural change, introduce numbered migrations at
that point rather than changing an existing bootstrap statement and assuming
`IF NOT EXISTS` will alter the table.

## Known Limitations and Follow-ups

### Reconciliation scope

`ending_balance` is parsed statement data. The current Allium rule compares it
with `account.current_balance` when the statement is confirmed. That is an
account-wide value, so it can be incorrect when transactions after the
statement period have already been confirmed. This document preserves the
specified behavior rather than adding an unapproved as-of balance field.

Before reconciliation is relied on for historical statements, the behavioural
specification should decide whether to add a statement-period/as-of balance
calculation and how to persist or display a mismatch. `ReconciliationMismatch`
is currently an emitted event, not a stored entity.

### Starting balance date

`starting_balance` has no date in the current entity. The implementation must
document that it is the baseline for all imported transactions included in the
derived balance. A future change that supports arbitrary historical imports
may need an effective timestamp or a separate balance snapshot model.

### Categorization ties

The model stores the keyword and target category needed for case-insensitive
substring matching and longest-keyword priority. The specification does not
define how to break a tie between distinct matching keywords of equal length;
the categorizer must define that before relying on deterministic results.

### Budget uniqueness and nullable targets

The database unique constraint protects category-targeted budgets. The
notebook's budget create/edit operation must separately check for an existing
overall budget with the same period because `NULL` values are not equal for
ordinary SQL uniqueness checks.

### Query indexes

The listed indexes cover the known account, category, status, date, statement,
and budget-pacing access paths. Case-insensitive arbitrary substring matching
against merchant text is expected to scan rows; it should not receive a
misleading ordinary index. Additional indexes should be added only after a
real query pattern or profiling result justifies them.
