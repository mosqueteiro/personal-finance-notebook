# Personal Finance Notebook

A local, interactive Marimo notebook for tracking account liquidity, ingesting transactions from bank/credit-card statements, auto-categorizing spending, and monitoring budget pacing.

> For the **Efficient Family CFO** who needs household stability and long-term wealth without losing family time: a 5-minute weekly status pulse plus a foundation for long-term planning.

## Status

**v1 MVP** — in progress. See `docs/InformationProductCanvas.md` for the full product canvas and `specs/personal-finance-notebook.allium` for the behavioural specification.

- **Will:** Multi-format ingestion (CSV/PDF), DuckDB persistence, basic keyword categorization, single-user local state, filtered ledger, budget pacing, low-balance alerts.
- **Won't (v1):** Direct API connections (Plaid), real-time stock/crypto prices, multi-user auth, ML auto-categorization (deferred to v2).
- **Future (v2):** Goal sliders for savings forecasting, "Kill List" for subscription detection.

## Prerequisites

**Nix is optional.** The project is developed with [devenv](https://devenv.sh) on the [Nix](https://nixos.org) package manager, but the Python project itself is portable — `pyproject.toml` and `uv.lock` let you run it on any system with Python 3.14+ and [uv](https://github.com/astral-sh/uv).

### Recommended: devenv (Nix)
- The [Nix](https://nixos.org) package manager with flakes enabled — this is just the package manager, **not** NixOS the OS.
- [devenv](https://devenv.sh) ≥ 2.1

### Alternative: uv directly (no Nix)
- Python 3.14+
- [uv](https://github.com/astral-sh/uv)
- Run `uv sync`, then `marimo edit`

## Quick start

### With devenv (recommended)

```sh
devenv shell      # enter the env (auto-runs `uv sync`)
devenv up         # launch `marimo edit` — opens the notebook in your browser
```

### Without Nix

```sh
uv sync           # install dependencies from uv.lock
marimo edit       # launch the notebook
```

Add dependencies (either path):

```sh
uv add <package>
```

## Project layout

```
.
├── devenv.nix              # dev environment (Python 3.14, uv, marimo process)
├── devenv.yaml             # devenv inputs (nixpkgs, nixpkgs-python)
├── pyproject.toml          # project + uv dependencies
├── docs/                   # product canvas and other docs
├── specs/                  # Allium behavioural specification (source of truth)
└── notebooks/              # Marimo notebooks (planned)
```

## Data & persistence

- **Data sources:** local CSV and PDF statements exported from banks/credit cards.
- **State storage:** `finance.db` (DuckDB) — single-user, local only.

## Tech stack

| Layer        | Choice                                          |
|--------------|-------------------------------------------------|
| UI           | [Marimo](https://marimo.io) reactive notebook   |
| Persistence  | [DuckDB](https://duckdb.org) (`finance.db`)     |
| Packaging    | [uv](https://github.com/astral-sh/uv)           |
| Environment  | [devenv](https://devenv.sh) on Nix              |
| Python       | 3.14                                            |

## License

MIT — see [LICENSE](LICENSE).
