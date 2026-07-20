# AGENTS.md

Guidance for AI agents (and humans pairing with them) working in this repo.

## What this project is

A single-user, local-first **Marimo notebook** backed by **DuckDB** for personal finance: account liquidity, transaction ingestion (CSV/PDF), keyword categorization, and budget pacing. See [README.md](README.md) and [ARCHITECTURE.md](ARCHITECTURE.md) for the full picture.

## Source of truth

- **`specs/personal-finance-notebook.allium`** — behavioural specification. The domain model, status lifecycles, rules, and surfaces live here. Treat it as authoritative for *what* the system does.
- **`docs/InformationProductCanvas.md`** — product context, personas, scope (will/won't).
- **`ARCHITECTURE.md`** — how the spec maps to layers and modules.

When a change touches behaviour, update the spec first (or confirm the spec already permits it), then implement. Do not let the spec and code drift.

## Environment

This project uses [devenv](https://devenv.sh). Python 3.14 + uv are managed by it — do **not** install Python or dependencies system-wide.

```sh
devenv shell      # enter env; auto-runs `uv sync`
devenv up         # launch `marimo edit` (the notebook UI)
devenv test       # build env + run enterTest + git hooks (CI parity)
```

Add Python deps with `uv add <pkg>` inside the shell (updates `pyproject.toml` + `uv.lock`).

## Commands

| Task                | Command                                       |
|---------------------|-----------------------------------------------|
| Enter env           | `devenv shell`                                |
| Run notebook        | `devenv up`                                   |
| Add a dependency    | `uv add <pkg>` (inside the shell)             |
| Type-check          | `pyright` (available in env; no config yet)   |
| CI parity check     | `devenv test`                                 |
| Run a notebook cell | via `marimo edit` UI (no CLI test runner yet) |

There is no `pytest`/`ruff` config yet — if you add one, record the commands here and wire them into `devenv.nix` (`enterTest`, `git-hooks`) so `devenv test` stays meaningful.

## Conventions

- **Python 3.14**, declared in `devenv.nix` (`languages.python.version`) and `pyproject.toml` (`requires-python`). Keep both in sync.
- **uv is the only package manager.** Do not introduce `pip`/`poetry`/`pipenv`. Poetry and uv are mutually exclusive in devenv.
- **No comments in code** unless asked. Prefer clear names and small functions.
- **No external API integrations** (Plaid, price feeds, etc.) — v1 is file-ingestion only. See the "Won't" list in the canvas.
- **Single-user, local state.** Do not add auth, multi-tenancy, or network services.
- **Keyword categorization only.** ML auto-categorization is deferred to v2 — don't implement it now.
- **Start with one notebook.** Keep UI, SQL, and logic together in a single Marimo notebook. Only extract to Python modules if the notebook gets unwieldy.

## Before finishing a task

1. Run `devenv test` and make sure it passes.
2. If you changed behaviour, update `specs/personal-finance-notebook.allium` and `ARCHITECTURE.md` to match.
3. If you changed `devenv.nix` or `pyproject.toml`, verify with `devenv shell python -V` and a quick `uv sync`.
4. Do **not** commit unless explicitly asked. Never commit `devenv.local.nix` or `devenv.local.yaml`.
5. Commit `devenv.lock` and `uv.lock` for reproducibility.

## Commit style

Short, conventional-subject commits scoped by area, e.g.:

```
[devenv] configure devenv and pyproject for marimo and duckdb
[spec] add CategorizationRule entity
[ingestion] add CSV parser for bank statements
```

Match the existing `git log` style.
