# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small Python package that extracts dog breed data from The Dog API
(`https://api.thedogapi.com/v1/breeds`) and either writes it to JSON/CSV,
loads it into a warehouse (BigQuery, via dlt), or transforms the loaded
data (via dbt-core, in `transform/`).

## Commands

```bash
# Setup (editable install with dev deps)
python -m venv .venv.nosync
source .venv.nosync/bin/activate
pip install -e ".[dev]"

# Run the extractor
dogs4heyra-extract                  # writes breeds.json
dogs4heyra-extract -o breeds.csv    # writes CSV instead

# Load into a warehouse (dlt)
pip install -e ".[warehouse]"
dogs4heyra-load                     # loads into BigQuery (default)
dogs4heyra-load --destination duckdb --dataset dog_breeds  # load locally instead

# Transform with dbt
pip install -e ".[transform]"
eval "$(.venv.nosync/bin/python scripts/print_bq_env.py)"  # BQ_* env vars from .dlt/secrets.toml
dbt run --project-dir transform --profiles-dir transform
dbt test --project-dir transform --profiles-dir transform

# Tests
pytest                              # full suite
pytest tests/test_extract.py::test_write_csv_flattens_nested_fields  # single test
```

An API key is **required** by the live API (`/breeds` returns 403 without
one). Set it via `DOG_API_KEY` env var or `--api-key` flag; get a free key
at https://thedogapi.com. Tests do not need a real key — they mock HTTP
calls with the `responses` library, so `pytest` works offline.

BigQuery credentials go in `.dlt/secrets.toml` (gitignored, never
committed) — see `transform/profiles.yml` for the exact field names it
expects.

The venv is `.venv.nosync`, not `.venv`: this project lives under
`~/Desktop`, which iCloud Drive sync may manage, and it re-hides pip's
editable-install `.pth` file after syncing — Python 3.12+'s `site.py`
silently skips hidden `.pth` files, breaking `import dogs4heyra` with no
error message. `.nosync` is a naming convention iCloud sync respects to
skip a folder. If this ever recurs (`ModuleNotFoundError: No module named
'dogs4heyra'` despite a successful `pip install -e .`), check
`ls -lO .venv.nosync/lib/*/site-packages/__editable__*.pth` for a `hidden`
flag.

## Architecture

Two entry points sharing one HTTP call:

- `src/dogs4heyra/extract.py` — `fetch_breeds()` hits the API and returns
  the raw parsed JSON list (one dict per breed, unmodified). `_flatten()`
  (CSV path only) pulls the API's nested `weight`/`height`/`image` dicts
  into flat columns per `CSV_FIELDS`; JSON output is written as-is,
  un-flattened. `main()` is the `dogs4heyra-extract` CLI — picks JSON vs
  CSV from `--format`, falling back to the `-o/--output` extension.
- `src/dogs4heyra/pipeline.py` — wraps `fetch_breeds()` in a dlt
  `@dlt.resource` (`breeds_resource`) and runs it through a dlt pipeline
  (`write_disposition="append"`, so raw accumulates a full snapshot per
  run rather than being overwritten — the same breed id can span many
  raw rows over time; `stg_breeds` in `transform/` is what collapses that
  back down). `main()` is the `dogs4heyra-load` CLI. dlt infers the
  warehouse schema from the raw JSON automatically — no manual schema or
  flattening needed here, unlike the CSV path in `extract.py`.

If the API response shape changes (new/renamed fields), only
`CSV_FIELDS`/`_flatten()` in `extract.py` need updating — both the JSON
output and the dlt pipeline pass the API payload through unmodified.

Test coverage for the pipeline runs against local DuckDB (`tests/test_pipeline.py`),
not BigQuery — no live credentials are needed for `pytest` to pass. That
test pins `pipelines_dir` to `tmp_path`; without it, dlt persists local
pipeline state under `~/.dlt/pipelines/<pipeline_name>` across test runs
and can end up pointing at a stale, already-deleted pytest tmp folder
from a previous run, breaking the test non-deterministically.

`transform/` is a separate dbt-core project (own `dbt_project.yml`,
`profiles.yml`, invoked with `--project-dir transform --profiles-dir
transform`, not activated via `cd`). It treats `raw.breeds`
(`dog_breeds.breeds` in BigQuery — the table `dogs4heyra-load` writes) as
a dbt **source**: read-only, never written to or dropped, so it stays the
full historical/reference layer. `stg_breeds`
(`transform/models/staging/stg_breeds.sql`) is a view built on top of it
in a separate `dog_breeds_staging` dataset — safe to rebuild or drop
without touching raw. `profiles.yml` has no secrets in it (values come
from `BQ_PROJECT_ID`/`BQ_CLIENT_EMAIL`/`BQ_PRIVATE_KEY` env vars via
Jinja `env_var()`), so it's committed; `scripts/print_bq_env.py` derives
those three env vars from `.dlt/secrets.toml` so credentials are entered
once, not duplicated between dlt and dbt config.

`stg_breeds` collapses raw's full append history to one current-state row
per breed. It does this in two stages, both in the same file: first a
`merged` CTE computes, per column, `last_non_null(column)`
(`transform/macros/last_non_null.sql` — a
`LAST_VALUE(... IGNORE NULLS) OVER (PARTITION BY id ORDER BY
_dlt_load_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)`
window), which independently forward-fills each column across that
breed's full history — deliberately per-column, not per-row, so a null
in the latest load doesn't clobber a real value an earlier load had for
some *other* field. `qualify row_number() ... = 1` then collapses the
now-identical-per-breed rows down to one. Only after that does a second
CTE do the renaming/type-parsing that was already there. `perfect_for` is
added as a column but has never had a non-null value in any load so far
— dlt hasn't materialized it into raw yet, so the model checks for its
presence via `adapter.get_columns_in_relation()` at compile time and
substitutes a literal `NULL` if it's absent, rather than hard-referencing
a column that may not exist (which would error, not just return nulls).
It'll start picking up real values automatically once raw actually has
any.

The API's numeric fields (life span, weight, height) are inconsistently
formatted free text — plain ranges ("23-25"), decimals ("3.2-4.5"), and
gender-split ranges ("Male: 25-30; Female: 20-25") all appear in the same
column. `extract_min_number`/`extract_max_number`
(`transform/macros/extract_number_range.sql`) handle all three by
extracting every number in the string and taking min/max, rather than
assuming one fixed pattern — an earlier version used a single regex
anchored to the string start, which silently returned NULL for most
gender-split rows.
