# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small Python package that extracts dog breed data from The Dog API
(`https://api.thedogapi.com/v1/breeds`) and either writes it to JSON/CSV
or loads it into a warehouse (BigQuery, via dlt).

## Commands

```bash
# Setup (editable install with dev deps)
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# Run the extractor
dogs4heyra-extract                  # writes breeds.json
dogs4heyra-extract -o breeds.csv    # writes CSV instead

# Load into a warehouse (dlt)
pip install -e ".[warehouse]"
dogs4heyra-load                     # loads into BigQuery (default)
dogs4heyra-load --destination duckdb --dataset dog_breeds  # load locally instead

# Tests
pytest                              # full suite
pytest tests/test_extract.py::test_write_csv_flattens_nested_fields  # single test
```

An API key is **required** by the live API (`/breeds` returns 403 without
one). Set it via `DOG_API_KEY` env var or `--api-key` flag; get a free key
at https://thedogapi.com. Tests do not need a real key — they mock HTTP
calls with the `responses` library, so `pytest` works offline.

BigQuery credentials go in `.dlt/secrets.toml` (gitignored; copy
`.dlt/secrets.toml.example` and fill it in) — never committed.

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
  (`write_disposition="replace"`, so each run overwrites the table rather
  than appending). `main()` is the `dogs4heyra-load` CLI. dlt infers the
  warehouse schema from the raw JSON automatically — no manual schema or
  flattening needed here, unlike the CSV path in `extract.py`.

If the API response shape changes (new/renamed fields), only
`CSV_FIELDS`/`_flatten()` in `extract.py` need updating — both the JSON
output and the dlt pipeline pass the API payload through unmodified.

Test coverage for the pipeline runs against local DuckDB (`tests/test_pipeline.py`),
not BigQuery — no live credentials are needed for `pytest` to pass.
