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
| Gold | `gold_breeds`, `gold_breeds_excluded`, `gold_weight_class_summary` | `dog_breeds_gold` | Curated, quality-**filtered** breed dimension (+ its audit trail) and a weight-class rollup, all materialized as tables — the cleanest layer, meant for reporting |

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

## Scheduled daily load

`.github/workflows/daily-load.yml` runs `dogs4heyra-load` (extract +
append into raw) followed by `dbt build` (bronze → silver → gold) every
day at 2am UTC, plus a `workflow_dispatch` trigger for on-demand manual
runs (`gh workflow run daily-load.yml`). Needs `DOG_API_KEY` in addition
to the `BQ_*` secrets the CI `dbt` job uses — same secrets, but exposed
under two different naming conventions, since dlt
(`DESTINATION__BIGQUERY__CREDENTIALS__*`) and dbt (`BQ_*` via
`profiles.yml`'s `env_var()`) each expect their own env var names.

## Example analysis

Answered against `dog_breeds_gold.gold_breeds` (630 breeds, current as
of the load this was run against).

**Which breeds have the longest predicted life span?** ("Predicted"
here = midpoint of `life_span_min_years`/`life_span_max_years`.) A
five-way tie at 15 years: Silken Windhound, Koolie, Miniature Fox
Terrier, Denmark Feist, and Rat Terrier — all small-to-medium breeds
across different breed groups (Hound, Herding, Terrier, Scenthound).

```sql
select breed_name, breed_group, life_span_min_years, life_span_max_years,
       round((life_span_min_years + life_span_max_years) / 2, 1) as predicted_life_span_years
from dog_breeds_gold.gold_breeds
where life_span_min_years is not null and life_span_max_years is not null
order by predicted_life_span_years desc, life_span_max_years desc
limit 10
```

**How are breeds distributed across weight classes?** Buckets are on
`weight_metric_max_kg`: Small ≤10kg, Medium 10–25kg, Large 25–45kg,
Giant >45kg. This one's now a real dbt model —
[`gold_weight_class_summary`](transform/models/gold/gold_weight_class_summary.sql)
— rather than a one-off query, so it's always current and queryable
directly (e.g. by a dashboard):

| Weight class | Breeds | % of total | Avg weight (kg) | Avg predicted life span (yrs) |
|---|---|---|---|---|
| Small (≤10kg) | 93 | 14.8% | 5.3 | 13.4 |
| Medium (10–25kg) | 211 | 33.5% | 16.0 | 13.0 |
| Large (25–45kg) | 241 | 38.3% | 27.7 | 12.4 |
| Giant (>45kg) | 83 | 13.2% | 51.9 | 10.8 |
| Unknown (no parseable weight) | 2 | 0.3% | — | 12.5 |

Large is the single biggest bucket, but Medium+Large together account
for ~72% of all breeds. (`avg_weight_kg` is null for Unknown — those 2
breeds have no parseable weight to average at all.)

**What are the top temperaments among family-friendly breeds
(`good_for_families = true`)?** Worth being upfront about a bit of
circularity here: `good_for_families` is itself defined by the presence
of traits like `affectionate`/`friendly`/`gentle` (see
`transform/models/silver/silver_breeds.yml`), so of course those top the
list. The more informative view is what *else* commonly co-occurs:

| Trait | Family-friendly breeds with it |
|---|---|
| intelligent | 359 |
| loyal | 278 |
| alert | 224 |
| energetic | 184 |
| courageous | 109 |
| independent | 97 |
| confident | 91 |
| protective | 76 |

`intelligent`, `loyal`, and `alert` are near-universal across the whole
dataset (not just family-friendly breeds), so their presence here mostly
reflects how common they are overall rather than a specific
family-friendly signature — `energetic` (184) is the more genuinely
interesting co-occurrence, since it cuts against a naive assumption that
"family-friendly" implies "low-energy."

**Is there a relationship between size and life span?** Yes — a
moderate-to-strong negative correlation: **−0.61** between
`weight_metric_max_kg` and `life_span_max_years` (**−0.67** using the
midpoint of each range instead of just the max). It also shows up
cleanly as a monotonic trend across `gold_weight_class_summary`'s
`avg_life_span_years` column above (13.4 → 13.0 → 12.4 → 10.8 as weight
class increases). Bigger breeds predictably live shorter lives, in this
dataset — a well-known pattern in dog biology, not a data artifact.
