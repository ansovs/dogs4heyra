# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small Python package that extracts dog breed data from The Dog API
(`https://api.thedogapi.com/v1/breeds`) and writes it to JSON or CSV.

## Commands

```bash
# Setup (editable install with dev deps)
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# Run the extractor
dogs4heyra-extract                  # writes breeds.json
dogs4heyra-extract -o breeds.csv    # writes CSV instead

# Tests
pytest                              # full suite
pytest tests/test_extract.py::test_write_csv_flattens_nested_fields  # single test
```

An API key is **required** by the live API (`/breeds` returns 403 without
one). Set it via `DOG_API_KEY` env var or `--api-key` flag; get a free key
at https://thedogapi.com. Tests do not need a real key — they mock HTTP
calls with the `responses` library, so `pytest` works offline.

## Architecture

Single module: `src/dogs4heyra/extract.py`.

- `fetch_breeds()` — hits the API, returns the raw parsed JSON list (one
  dict per breed, unmodified).
- `_flatten()` — only used by the CSV path. The API's `weight`, `height`,
  and `image` fields are nested dicts; this pulls them into flat columns
  (`weight_imperial`, `weight_metric`, `image_url`, etc.) per `CSV_FIELDS`.
  JSON output is *not* flattened — it's written as-is from the API.
- `main()` — CLI entry point (`dogs4heyra-extract`). Picks JSON vs CSV from
  `--format`, falling back to the `-o/--output` file extension.

If the API response shape changes (new/renamed fields), update
`CSV_FIELDS` and `_flatten()` together — JSON output needs no changes
since it passes the API payload through untouched.
