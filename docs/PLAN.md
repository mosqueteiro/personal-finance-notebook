# Plan: Personal Finance Notebook

Living document. Tracks planning status from current artifacts through to "ready for implementation."

---

## Current state (what's done)

| Artifact | Status | Notes |
|---|---|---|
| Information Product Canvas | ✅ Done | `docs/InformationProductCanvas.md` — personas, business questions, will/won't, scope |
| Allium behavioural spec | ⚠️ Draft | `specs/personal-finance-notebook.allium` — entities, rules, surfaces. Gaps noted below |
| High-level architecture | ⚠️ Draft | `ARCHITECTURE.md` — layering, data model summary, key flows. Needs updates after spec revision |
| Repo bootstrap | ✅ Done | devenv + uv + Python 3.14 + marimo + duckdb; README, AGENTS.md, git |
| Quality tooling | ❌ Not started | No ruff, basedpyright, or pytest configs yet |

---

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Module structure | **Pure notebook** | Per AGENTS.md. Extract to Python modules later only if the notebook becomes unwieldy |
| Ingestion scope | **Pluggable adapter pattern** | No concrete institutions in scope for v1. Design a registration process so institutions can be added later without core changes |
| Account balance | **Stored + reconciled** | `current_balance` stored on `Account`. Auto-reconcile against parsed ending balance from PDF/CSV when possible, manual fallback when not |
| Currency | **USD only** | No currency field on Transaction or Account |
| Quality tooling | **Set up now** | `ruff`, `basedpyright`, `pytest` — configs in `pyproject.toml`, wired into `devenv.nix` `enterTest` + git hooks. Set the bar before code is written |

---

## Planning deliverables

These are the artifacts still needed. Once all are complete, Phase 0 (implementation) can begin.

- [ ] **1. Spec revision** — close gaps in `specs/personal-finance-notebook.allium`
- [ ] **2. Data model** — conceptual → logical → physical progression, modeling techniques, DuckDB DDL
- [ ] **3. Ingestion adapter design** — adapter contract, registration process, dedup, auto-reconciliation flow
- [ ] **4. Categorization semantics** — match mode, priority, fallback, reapply
- [ ] **5. Budget pacing semantics** — period selection, pacing math, rollup rules
- [ ] **6. Notebook layout sketch** — cell-by-cell surface mapping, widgets, mutation flow
- [ ] **7. Quality setup** — ruff + basedpyright + pytest configs, devenv wiring
- [ ] **8. Implementation backlog** — phased sequence (this document)

---

## Spec gaps to close (deliverable 1)

The current Allium spec is a solid draft. These gaps must be resolved before the physical schema can be derived.

### Missing identity
- No `id` on any entity. Need a surrogate key strategy. Open: `UUID` vs `INTEGER IDENTITY`?

### Account.current_balance is unmaintained
- The spec stores `current_balance` on `Account` but no rule updates it from confirmed transactions. Need:
  - `Account.starting_balance` field (user-provided seed balance)
  - A rule: `current_balance = starting_balance + SUM(confirmed transactions)`
  - A reconciliation concept against statement ending balance

### AccountStatement lacks reconciliation fields
- No `ending_balance` field to reconcile against. Need:
  - `AccountStatement.ending_balance: Decimal?` — parsed from statement when available
  - A rule or surface action: reconcile statement → compare parsed vs computed balance → flag mismatches

### UploadStatement lacks file content
- `UploadStatement` carries `file` (a name?) but not the content or path. Extraction needs the actual bytes. Need to define: does the trigger carry a file path? A file handle? How does the adapter receive it?

### categorize() is undefined
- `categorize(merchant)` is referenced in two rules but never defined as an operation. Need:
  - Match semantics: case-insensitive substring match? Whole-word? Regex?
  - Priority: longest keyword wins? First-inserted wins? Most-specific?
  - Fallback: what happens when no rule matches? Return null (uncategorized)? Create an "Uncategorized" category?
  - Should it be a named `operation` in the spec?

### No deduplication rule
- Re-uploading the same statement creates duplicate transactions. Need:
  - A dedup key (e.g. account + file_name + date range, or content hash)
  - A rule: reject upload if dedup key already exists, or warn and offer override

### No manual category override
- `ReapplyCategorizationRules` exists but there's no explicit "edit category on a confirmed transaction" operation. If a user corrects a category manually, what happens? Is it overwritten on reapply?

### Budget "current period" is undefined
- `Budget.period` exists (monthly/yearly) but there's no concept of what "current period" means. Need:
  - Does the user pick a date window, or is "current calendar month" the default?
  - Pacing math: linear day-of-month projection? Or just spent-vs-budget snapshot?
  - Overall budget (null `target_category`) rollup semantics vs category budgets

### requires: violation surfacing
- Several rules have `requires:` guards. What happens in the UI when a violation occurs? Toast notification? Inline error? Modal dialog?

---

## Sequenced planning workflow

Each step produces a committed artifact and builds on the previous one.

### Step 1: Tend the Allium spec
Close all gaps listed above. Commit as `[spec] close planning gaps: ids, balance rules, reconciliation, categorize semantics, dedup, pacing`

### Step 2: Produce data model document (`docs/data-model.md`)
A single document covering three layers — from abstract to concrete — plus modeling techniques:

**Conceptual model** — entity-relationship view derived from the Allium spec:
- Entities and their attributes
- Relationships (one-to-many, many-to-many)
- Business rules that shape the model (e.g. `is_low_balance` derived from `current_balance < low_balance_threshold`)

**Logical model** — technology-agnostic refinement:
- Surrogate key strategy (`UUID` vs `INTEGER IDENTITY`)
- Attribute types and constraints (required vs optional, ranges, unique)
- Status lifecycle representation patterns
- Derived fields: where they live (stored column, computed column, app-level, view)
- Referential integrity (FKs, cascade behavior on delete/update)
- Naming conventions (snake_case, singular/plural, audit columns)

**Physical model** — DuckDB-specific DDL:
- `CREATE TABLE` statements with DuckDB types (`DECIMAL(18,2)` for currency, `TIMESTAMP` for dates, `VARCHAR` or native `ENUM` for status fields)
- Primary keys, foreign keys, unique constraints
- Indexes for query patterns (filter by account/merchant/category/date range; budget pacing window scans)
- Derived column strategy (computed vs app-level vs view) for `is_low_balance`
- Schema bootstrap strategy: DDL-on-notebook-startup vs `migrations/` folder

**Modeling techniques** — conventions and rationale:
- How status lifecycles are modeled in the schema (VARCHAR + CHECK vs native ENUM)
- Derived fields pattern: when to use computed columns vs app-level
- Audit columns (`created_at`) convention; whether `updated_at` is needed
- Currency precision and rounding strategy (`DECIMAL(18,2)` rationale)
- Nullable foreign keys for optional relationships
- Surrogate vs natural key tradeoffs for this project
- Naming conventions: snake_case, singular table names, Python pluralization

**Deliverable:** `docs/data-model.md`

### Step 3: Design ingestion adapter contract + reconciliation
Define the adapter interface that institutions plug into:
- Registration process (how to add a new institution)
- Adapter contract: what it receives (file path, format, account context) and returns (list of extracted entries)
- Dedup strategy (key-based duplicate detection)
- Auto-reconciliation flow: parse ending balance from statement → compare to computed balance → surface mismatch to user
- Manual fallback: when ending balance isn't parseable, prompt user to enter it

**Deliverable:** `docs/ingestion.md` or ARCHITECTURE section

### Step 4: Define categorization + budget pacing semantics
**Categorization:**
- Match mode (case-insensitive substring)
- Priority rule (longest keyword wins)
- Fallback (`Uncategorized` category)
- Reapply behavior: does reapply override a manual correction?

**Budget pacing:**
- Period: calendar month/year only (v1), with option for arbitrary window (v2)
- Pacing math: linear day-of-month projection (spend-so-far / day-number * days-in-month) vs simple snapshot
- Overall vs category budget rollup semantics
- No rollover in v1

**Deliverable:** ARCHITECTURE sections

### Step 5: Sketch notebook cell layout
Map each Allium surface to a Marimo notebook section:
- **Glance Header:** liquidity summary cards + low-balance alerts (read-only)
- **Data Ingestion:** file upload widget, statement table with status, confirm/reject buttons
- **Categorized Ledger:** filterable transaction table (by account, merchant, category, date)
- **Categorization Management:** rule editor (add/keyword/category), reapply button
- **Budget & Pacing:** budget table, spending-vs-budget bars/charts, date range picker

Define widget types, mutation flow (which cell triggers re-runs), and how state propagates.

**Deliverable:** `docs/notebook-layout.md`

### Step 6: Set up quality tooling
- Add `[tool.ruff]` config to `pyproject.toml` (line length, rules selection)
- Add `[tool.basedpyright]` config to `pyproject.toml` (python version, type checking strictness)
- Add `[tool.pytest.ini_options]` to `pyproject.toml` (test paths, markers)
- Create a minimal `tests/` directory with a placeholder test
- Wire into `devenv.nix`: `enterTest` should run `pytest` (or the relevant subset)
- Add git hooks via devenv (pre-commit: ruff + basedpyright; pre-push: pytest)

**Deliverable:** Updated `pyproject.toml`, `devenv.nix`, placeholder `tests/` directory

### Step 7: Finalize implementation backlog
Update this document with phased implementation steps (see below), each independently shippable.

**Deliverable:** Updated `docs/PLAN.md`

---

## Implementation phases

Detailed after step 7. Preview:

| Phase | Scope | Depends on |
|---|---|---|
| **0** | Schema bootstrap + DuckDB connection helper | Steps 1–2 |
| **1** | Reference data CRUD: Account (with starting_balance), Category, Budget | Phase 0 |
| **2** | CSV ingestion via adapter pattern (one sample fixture format) | Phase 0, step 3 |
| **3** | Categorization rules + auto-categorize on Transaction.created | Step 4 |
| **4** | Confirm/reject flow with cascading transaction status + balance maintenance | Steps 1, 4 |
| **5** | Auto-reconciliation from parsed ending balance (manual fallback) | Steps 3, 5 |
| **6** | Budget pacing queries + Glance Header + low-balance alerts | Steps 4, 5, 6 |
| **7** | PDF ingestion (add pdfplumber, second format) | Phase 2 |
| **8** | Polish: property-based tests (propagate skill), docs, README walkthrough | Steps 6, 7 |

---

## Open questions (to resolve during steps 1–7)

**Spec:**
- [ ] `UUID` vs `INTEGER IDENTITY` for surrogate keys?
- [ ] Categorization: case-insensitive substring, longest keyword wins, `Uncategorized` fallback — confirmed?
- [ ] Budget period: calendar month/year only, or arbitrary window?
- [ ] Pacing math: linear day-of-month projection, or snapshot only?
- [ ] When no categorization rule matches: null or explicit "Uncategorized" category?
- [ ] Does `ReapplyCategorizationRules` override manual corrections?

**Implementation:**
- [ ] PDF parsing library: `pdfplumber` — OK to add as a dep?
- [ ] Schema bootstrap: DDL-on-notebook-startup vs `migrations/` folder?
- [ ] `requires:` violation UX: toast / inline / modal?
- [ ] How does the file content reach the adapter? (file path in trigger, or marimo upload widget reference?)

---

## Ready-for-implementation checklist

All of these must be true before Phase 0 begins:

- [ ] All spec gaps closed (steps 1)
- [ ] Data model produced and reviewed (step 2)
- [ ] Ingestion adapter contract defined (step 3)
- [ ] Categorization + pacing semantics documented (step 4)
- [ ] Notebook layout sketched (step 5)
- [ ] Quality tooling wired in (step 6)
- [ ] `devenv test` passes
- [ ] Implementation backlog finalized (step 7)
