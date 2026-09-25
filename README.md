# dogs4heyra

Extracts dog breed data from [The Dog API](https://api.thedogapi.com/v1/breeds).

## Setup

```bash
python -m venv .venv.nosync
source .venv.nosync/bin/activate
pip install -e ".[dev]"
```

The venv is named `.venv.nosync` rather than `.venv` because this project
lives under `~/Desktop`, which iCloud Drive's "Desktop & Documents" sync
may manage — the `.nosync` suffix is a convention iCloud sync respects to
skip a folder. Without it, iCloud re-hides pip's editable-install `.pth`
file after every sync, which breaks imports on Python 3.12+ (site.py
silently skips hidden `.pth` files). If you move this project outside an
iCloud-synced folder, a plain `.venv` works fine too.

An API key is required for the `/breeds` endpoint. Get a free one at
https://thedogapi.com and set it via:

```bash
export DOG_API_KEY=your-key-here
```

## Usage

```bash
dogs4heyra-extract                          # writes breeds.json
dogs4heyra-extract -o breeds.csv             # writes CSV instead
dogs4heyra-extract -o data/all_breeds.json   # any output path
```

Or as a library:

```python
from dogs4heyra.extract import fetch_breeds

breeds = fetch_breeds()
```

## Loading to a warehouse (dlt + BigQuery)

```bash
pip install -e ".[warehouse]"
export DOG_API_KEY=your-key-here
dogs4heyra-load
```

This uses [dlt](https://dlthub.com) to load breed data into BigQuery's free
sandbox tier (no billing account required). Credentials go in
`.dlt/secrets.toml` (gitignored, not committed) — see `transform/profiles.yml`
for the field names it expects (`project_id`, `client_email`, `private_key`
under `[destination.bigquery.credentials]`); get them by creating a GCP
project, a service account with BigQuery Data Editor + Job User roles, and
a JSON key.

Each run **appends** a full snapshot rather than replacing the table, so
`dog_breeds.breeds` accumulates history across runs — the same breed can
span many rows over time. `bronze_breeds` (below) is what collapses that
back to one current row per breed. Override the destination/dataset with
`dogs4heyra-load --destination duckdb --dataset dog_breeds` to load locally
instead.

## Transforming with dbt (bronze / silver / gold)

The `transform/` directory is a dbt-core project. It reads the raw
`dog_breeds.breeds` table as a **source only** — dbt never writes to or
drops it, so raw stays intact as the historical reference layer. Each
medallion layer materializes into its own BigQuery dataset:

| Layer | Model | Dataset | What |
|---|---|---|---|
| Bronze | `bronze_breeds` | `dog_breeds_bronze` | Raw history collapsed to one current-state row per breed; cleaned, typed, numeric ranges parsed |
| Silver | `silver_breeds` | `dog_breeds_silver` | Clean passthrough of bronze for now — placeholder for future conformance/enrichment logic |
| Gold | `gold_breeds` | `dog_breeds_gold` | Clean passthrough of silver for now — placeholder for future aggregation/presentation logic |

```bash
pip install -e ".[transform]"
eval "$(.venv.nosync/bin/python scripts/print_bq_env.py)"   # reuses creds already in .dlt/secrets.toml
dbt run --project-dir transform --profiles-dir transform
dbt test --project-dir transform --profiles-dir transform
```

`bronze_breeds` (`transform/models/bronze/bronze_breeds.sql`) collapses
raw's full load history to **one current-state row per breed**: for each
column, independently, the most recent *non-null* value across that
breed's history wins (via the `last_non_null` macro,
`transform/macros/last_non_null.sql`) — no redundancy, no data loss, and
a null in the latest load doesn't clobber a real value from an earlier
one. It also cleans and types the raw columns, and parses the API's
free-text numeric fields (life span, weight, height — which mix plain
ranges, decimals, and gender-split "Male: X-Y; Female: A-B" formats) into
min/max columns via the `extract_min_number`/`extract_max_number` macros
(`transform/macros/extract_number_range.sql`).

## Tests

```bash
pytest
```

The pipeline test loads sample data into a local DuckDB file — no
BigQuery credentials are needed to run the test suite.
