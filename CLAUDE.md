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
dbt build --project-dir transform --profiles-dir transform  # run + test together

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
  raw rows over time; `silver_breeds` in `transform/` is what collapses
  that back down). `main()` is the `dogs4heyra-load` CLI. dlt infers the
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
full historical/reference layer. On top of that it's a medallion
architecture, one dataset per layer:

- **bronze** (`models/bronze/bronze_breeds.sql` → `dog_breeds_bronze`) —
  `select * from {{ source('raw', 'breeds') }}`, nothing else. Raw,
  untouched, full append history — one row per (breed, load), not
  deduplicated. Exists purely so raw is queryable through a model without
  ever being written to.
- **silver** (`models/silver/silver_breeds.sql` → `dog_breeds_silver`) —
  where the real logic lives: collapses bronze's history to one
  current-state row per breed, cleans/types columns, parses numeric
  ranges, and derives the `good_for_families`/`good_for_apartments` flags
  (see below).
- **gold** (`models/gold/` → `dog_breeds_gold`) — five tables (silver/
  bronze are views; gold is materialized since it's meant for repeated
  BI queries): `gold_breeds`, a curated, quality-**filtered** subset of
  silver's columns (not 1:1 with silver — see below); `gold_breeds_excluded`,
  its audit trail; `gold_weight_class_summary`, a rollup built on top of
  `gold_breeds` (breed count/avg weight/avg predicted life span per
  weight class); and `gold_breed_temperaments`/`gold_breed_groups`,
  bridge tables (one row per breed-trait or breed-group pair). All four
  non-`gold_breeds` tables are gold-on-gold, built from `ref('gold_breeds')`
  — not a 4th layer, just more models in the same one.

Don't assume bronze=raw-and-clean, silver=lightly-transformed the way an
earlier iteration of this project had it — that had bronze doing all of
silver's collapse/cleaning work while silver and gold were empty
passthroughs. It's been corrected to the arrangement above; keep new
logic in the layer it actually belongs to (raw mirror vs. current-state
cleaning vs. presentation), not bunched into whichever layer happens to
have the working code already.

Each `+schema:` in `dbt_project.yml` names its dataset directly — that
only works because `transform/macros/generate_schema_name.sql` overrides
dbt's default behavior, which would otherwise concatenate the profile's
target schema with `+schema` (e.g. `dog_breeds_bronze_bronze`) instead of
using it as the literal dataset name. `profiles.yml` has no secrets in it
(values come from `BQ_PROJECT_ID`/`BQ_CLIENT_EMAIL`/`BQ_PRIVATE_KEY` env
vars via Jinja `env_var()`), so it's committed; `scripts/print_bq_env.py`
derives those three env vars from `.dlt/secrets.toml` so credentials are
entered once, not duplicated between dlt and dbt config.

`silver_breeds` collapses bronze's full append history to one
current-state row per breed. It does this in three CTEs: first `merged`
computes, per column, `last_non_null(column)`
(`transform/macros/last_non_null.sql` — a
`LAST_VALUE(... IGNORE NULLS) OVER (PARTITION BY id ORDER BY
_dlt_load_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)`
window), which independently forward-fills each column across that
breed's full history — deliberately per-column, not per-row, so a null
in the latest load doesn't clobber a real value an earlier load had for
some *other* field. `qualify row_number() ... = 1` then collapses the
now-identical-per-breed rows down to one. `cleaned` does the
renaming/type-parsing, and `tagged` (last) derives the suitability
flags — kept last so they can reference `temperament_list` and
`weight_metric_max_kg` from `cleaned` directly. `perfect_for` is added as
a column but has never had a non-null value in any load so far — dlt
hasn't materialized it into bronze yet, so the model checks for its
presence via `adapter.get_columns_in_relation()` at compile time and
substitutes a literal `NULL` if it's absent, rather than hard-referencing
a column that may not exist (which would error, not just return nulls).
It'll start picking up real values automatically once bronze actually
has any.

The API's numeric fields (life span, weight, height) are inconsistently
formatted free text — plain ranges ("23-25"), decimals ("3.2-4.5"), and
gender-split ranges ("Male: 25-30; Female: 20-25") all appear in the same
column. `extract_min_number`/`extract_max_number`
(`transform/macros/extract_number_range.sql`) handle all three by
extracting every number in the string and taking min/max, rather than
assuming one fixed pattern — an earlier version used a single regex
anchored to the string start, which silently returned NULL for most
gender-split rows.

`life_span_avg_years`/`weight_metric_avg_kg` (also in `cleaned`) are the
midpoint of each breed's *own* min/max — per-breed, computed once per
row. Don't confuse these with `gold_weight_class_summary`'s
`avg_weight_kg`/`avg_life_span_years`, which average *across breeds
within a weight class* — a different aggregation entirely, that just
happens to reuse these columns as its input (see below). Because
BigQuery doesn't let a `SELECT` expression reference an alias defined
earlier in the same `SELECT` list, these recompute
`extract_min_number`/`extract_max_number` rather than referencing
`life_span_min_years`/`life_span_max_years` etc. directly — mildly
redundant, trivial at 631 rows.

`good_for_families`/`good_for_apartments` (in silver's `tagged` CTE) are
keyword rules against `temperament_list`, not the raw `description`/
`history` text — checked first, and only 2/631 breeds literally mention
"apartment" there, 50/631 mention "family", too sparse to key off of
directly. `good_for_apartments` also requires `weight_metric_max_kg <=
25` (roughly the dataset's median) and the absence of high-energy traits
(energetic/athletic/work-focused), not just presence of a calm trait —
without the exclusion, a breed tagged both "calm" and "energetic" would
otherwise qualify. Both are a first pass (documented as such in
`transform/models/silver/silver_breeds.yml`), not a validated
classification — expect to revisit the trait lists and the weight
threshold as real usage surfaces edge cases.

`gold_breeds` applies a row-level quality filter on top of silver — it
is deliberately not 1:1 with `silver_breeds`. The filter logic lives in
one place, `transform/macros/breed_quality_issues.sql`
(`breed_quality_issues()`), returning an array of human-readable reason
strings for a row (empty array = clean). Both `gold_breeds.sql`
(`where array_length(breed_quality_issues()) = 0`) and
`gold_breeds_excluded.sql` (`where array_length(...) > 0`) call the same
macro, so the filter and its audit trail structurally cannot drift apart
— update the macro, not either model, when the quality bar changes. The
macro mirrors `transform/tests/assert_silver_breeds_reasonable_*.sql`
and `assert_silver_breeds_temperament_not_empty.sql`; keep those in sync
by hand if you touch the macro's conditions. One more check the macro
does that has no standalone singular test: a `name_rank` column (row_number
partitioned by `breed_name`, ordered by `id`) computed in both gold
models flags anything but the first row per name as a duplicate — this
is what resolves silver's known "Caucasian Shepherd Dog" (ids 269 and
70) duplicate down to one row. Note `id` is a `STRING`, so this
tie-break is lexicographic, not numeric — `"269"` sorts before `"70"`,
which is why 269 is the one that ends up in `gold_breeds`. `dbt test`
includes `assert_gold_accounts_for_all_silver_rows`
(`transform/tests/`), which fails if any `silver_breeds.id` is missing
from both `gold_breeds` and `gold_breeds_excluded` (or appears in both)
— the reconciliation check that guarantees filtering never silently
drops a row.

`gold_weight_class_summary` reads from `ref('gold_breeds')`, not
`silver_breeds` or the source — so it only ever reflects the already
quality-filtered/deduplicated breed set, deliberately. Its weight
buckets come from the `weight_class` macro
(`transform/macros/weight_class.sql`), kept separate from
`breed_quality_issues` since it's a display grouping, not a quality
rule. `avg_weight_kg` is null for the "Unknown" bucket (2 breeds with no
parseable weight at all) — don't add a blanket `not_null` test on that
column, it'll fail; see the column-level note in
`gold_weight_class_summary.yml` for why. Its `avg_weight_kg`/
`avg_life_span_years` are `avg(gold_breeds.weight_metric_avg_kg)`/
`avg(gold_breeds.life_span_avg_years)` — averaging each breed's own
already-computed midpoint, not recomputing `(min + max) / 2` from
scratch. Mathematically identical either way (averaging is linear), just
without the duplicate expression.

`gold_breed_temperaments` (`transform/models/gold/gold_breed_temperaments.sql`)
is a plain `UNNEST(temperament_list)` — one row per (breed, trait).
`gold_breed_groups` (`transform/models/gold/gold_breed_groups.sql`) is
the same idea for `breed_group`, but that column isn't a clean list to
begin with — it's a single string that sometimes packs multiple
memberships ("Sighthound & Pariah") or uses a spelling/regional variant
of one group ("Pastoral/Herding", "Scent Hound" vs "Scenthound"). The
model splits on `&`, `/`, and `and` (case-insensitive, via
`REGEXP_REPLACE(breed_group, r'(?i)\s*(?:&|/|\band\b)\s*', '|')` then
`SPLIT(..., '|')` — BigQuery's `SPLIT()` doesn't take a regex directly,
hence the two-step normalize-then-split), then runs each resulting token
through `normalize_breed_group_token`
(`transform/macros/normalize_breed_group_token.sql`) for the pure
spelling variants that aren't actually compound (`"Mixed breed"` →
`"Mixed"`, `"Spitz-type"` → `"Spitz"`, etc. — each mapping confirmed
against the live distinct values before being added, not guessed). The
splitting behavior is deliberate: a breed with a compound value ends up
under *every* resulting group rather than one being picked as
"canonical" and the rest discarded — correct for genuine dual
membership, and harmless for the alternate-naming case (the breed's just
filterable under either name). Verified live: e.g. `"Scent Hound"` (2
breeds) + `"Scenthound"` (4 breeds) → 6 under `"Scenthound"` after
normalization; `"Sighthound & Pariah"` correctly adds its breed to both
`"Sighthound"` and `"Pariah"` counts, not a third bucket of its own.
Both bridge tables are built from `ref('gold_breeds')`, so — like
`gold_weight_class_summary` — they only ever reflect the already
quality-filtered, deduplicated breed set.

## CI

`.github/workflows/ci.yml` has two jobs. `test` (pytest) runs on every
push and PR, no credentials needed. `dbt` (`dbt build`, run+test
combined) runs against the live warehouse using
`BQ_PROJECT_ID`/`BQ_CLIENT_EMAIL`/`BQ_PRIVATE_KEY` repo secrets (set via
`gh secret set`, sourced from the same `.dlt/secrets.toml` fields
`scripts/print_bq_env.py` uses locally) — but only on pushes to `main`
(`if: github.ref == 'refs/heads/main' && github.event_name == 'push'`),
not feature branches or PRs. That gating is deliberate: there's one
shared BigQuery warehouse, not per-branch isolated datasets, so running
`dbt build` from multiple branches concurrently would mean concurrent
writes to the same bronze/silver/gold tables. If per-branch dbt runs are
ever needed, that requires either per-branch target datasets (e.g.
suffix `+schema` with a branch/PR identifier) or serializing the job,
not just removing the `if:` gate.
