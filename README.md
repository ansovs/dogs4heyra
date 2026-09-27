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
span many rows over time. `silver_breeds` (below) is what collapses that
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
| Bronze | `bronze_breeds` | `dog_breeds_bronze` | Raw, untouched, full append history — one row per (breed, load), not deduplicated |
| Silver | `silver_breeds` | `dog_breeds_silver` | Bronze's history collapsed to one current-state row per breed; cleaned, typed, numeric ranges parsed, plus heuristic `good_for_families`/`good_for_apartments` flags |
| Gold | `gold_breeds` | `dog_breeds_gold` | Curated, quality-**filtered** subset of silver, materialized as a table — the cleanest layer, meant for reporting |

```bash
pip install -e ".[transform]"
eval "$(.venv.nosync/bin/python scripts/print_bq_env.py)"   # reuses creds already in .dlt/secrets.toml
dbt build --project-dir transform --profiles-dir transform   # run + test together
```

`silver_breeds` (`transform/models/silver/silver_breeds.sql`) collapses
bronze's full load history to **one current-state row per breed**: for
each column, independently, the most recent *non-null* value across that
breed's history wins (via the `last_non_null` macro,
`transform/macros/last_non_null.sql`) — no redundancy, no data loss, and
a null in the latest load doesn't clobber a real value from an earlier
one. It also cleans and types the raw columns, and parses the API's
free-text numeric fields (life span, weight, height — which mix plain
ranges, decimals, and gender-split "Male: X-Y; Female: A-B" formats) into
min/max columns via the `extract_min_number`/`extract_max_number` macros
(`transform/macros/extract_number_range.sql`).

It also derives two heuristic suitability flags. Checked first: the raw
`description`/`history` text is too sparse to key off of directly (only
2/631 breeds literally mention "apartment", 50/631 mention "family"), so
both flags key off `temperament_list` instead — `good_for_families` if it
contains any of a curated set of family-friendly traits (affectionate,
friendly, gentle, playful, devoted, patient, docile, good-natured,
sweet-tempered, calm); `good_for_apartments` if it contains a low-energy
trait (calm, docile, adaptable, gentle, easygoing), none of the
high-energy traits (energetic, athletic, work-focused), and
`weight_metric_max_kg` is 25kg or under (roughly the dataset's median).
These are a first pass, not a validated classification — see
`transform/models/silver/silver_breeds.yml` for the exact rule.

`gold_breeds` (`transform/models/gold/gold_breeds.sql`) is **not** 1:1
with silver — it applies a row-level quality filter (the
`breed_quality_issues` macro, `transform/macros/breed_quality_issues.sql`):
sane life span/weight/height ranges, a non-empty temperament list, and
one row per `breed_name` (silver's known duplicate — "Caucasian Shepherd
Dog" under two ids — gets resolved to one row here rather than shown
twice on a dashboard). Nothing is silently dropped: every excluded row,
and why, lands in `gold_breeds_excluded` instead, and
`assert_gold_accounts_for_all_silver_rows` (a dbt test) fails if any
silver row is missing from both `gold_breeds` and `gold_breeds_excluded`.

## Tests

```bash
pytest
```

The pipeline test loads sample data into a local DuckDB file — no
BigQuery credentials are needed to run the test suite.

## CI

`.github/workflows/ci.yml` runs on every push:

- **`test`** (all branches/PRs): `pytest`, no credentials needed.
- **`dbt`** (pushes to `main` only): `dbt build` against the live
  warehouse, using `BQ_PROJECT_ID`/`BQ_CLIENT_EMAIL`/`BQ_PRIVATE_KEY`
  repo secrets. Restricted to `main` because there's one shared
  warehouse, not per-branch isolated datasets — running it on every
  feature branch/PR would risk concurrent writes to the same
  bronze/silver/gold tables.
