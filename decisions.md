# Decisions

Brief log of the choices made building this project, grouped by area, not
a step-by-step history. See CLAUDE.md/README.md for the resulting
architecture in detail.

## Environment

- Dev venv named `.venv.nosync`, not `.venv` — project sits under an
  iCloud-synced `~/Desktop`, and iCloud was re-hiding pip's editable-install
  file after every sync, silently breaking imports. `.nosync` is a naming
  convention iCloud respects to skip a folder, chosen over moving the whole
  project out of Desktop.
- GitHub repo created **private**.

## Extract & load

- dlt → **BigQuery free sandbox tier**, over DuckDB/MotherDuck/Postgres
  options, since it needs no billing account and the data stays queryable
  by SQL tools.
- Raw load uses `write_disposition="append"`, not `"replace"` — raw
  accumulates full history across runs rather than being overwritten, so
  there's something for the transform layer to collapse.
- Scheduled via GitHub Actions cron, **2am UTC literally** (not
  local/Copenhagen time — explicit choice to avoid DST-shift complexity),
  plus a manual `workflow_dispatch` trigger.

## Warehouse architecture (bronze / silver / gold)

- True medallion split, one BigQuery dataset per layer: bronze = untouched
  raw mirror; silver = current-state, one row per breed; gold = curated,
  quality-filtered, dashboard-ready.
- Silver's history-collapse is **per-column, not per-row**: the most recent
  non-null value per column wins independently, so a null in the latest
  load can't clobber a real value an earlier load had for some other
  field ("no redundancy, no data loss, latest wins").
- `id` kept as `STRING`, not cast to `INT64` — it's an identifier, not a
  quantity, and isn't numerically contiguous.
- Free-text numeric fields (life span, weight, height) parsed by
  extracting every number in the string and taking min/max, rather than a
  fixed-position regex — needed to handle gender-split ("Male: X-Y;
  Female: A-B") and decimal formats in the same column.
- Temperament normalized (lowercased, trimmed, deduplicated) — casing
  variants ("Alert" vs "alert") were inflating the distinct-trait count.
- `good_for_families`/`good_for_apartments` are heuristic flags keyed off
  `temperament_list`, not the raw `description`/`history` text — checked
  first, and the free text is too sparse (2/631 breeds mention
  "apartment", 50/631 "family") to be usable directly.
- Gold is **not** a passthrough of silver: a row-level quality filter
  excludes anything failing sanity checks or a duplicate `breed_name`.
  Nothing is silently dropped — every excluded row (and why) is logged in
  `gold_breeds_excluded`, with a test proving every silver row lands in
  exactly one of the two.
- `breed_group` synonyms/compounds ("Sighthound & Pariah", "Pastoral/
  Herding") are **split into multiple group memberships**, not collapsed
  to one canonical name — avoids a lossy judgment call and lets a breed
  with genuine dual membership show up under both.
- Added bridge tables (`gold_breed_temperaments`, `gold_breed_groups`) and
  a single denormalized `gold_breed_attributes` table, because separate
  bridge tables don't cross-filter each other in most BI tools — only
  charts sharing one data source do.

## Data quality & testing

- dbt tests grounded in live data, not guessed thresholds (e.g. life span
  range bounds set after checking the actual 5-18yr spread in the data).
- Test severity: `error` where gold guarantees an invariant by
  construction (e.g. `breed_name` uniqueness in gold); `warn` where it's a
  known, accepted upstream data issue (the same uniqueness check in
  silver, which deliberately doesn't dedupe).
- Every quality-filter/dedup decision paired with a reconciliation test
  (row counts must add up exactly across the split), not just spot-checked
  by hand.

## CI/CD

- Two separate GitHub Actions jobs: `pytest` on every push/PR (no
  credentials needed); `dbt build` gated to `main`-only pushes, since
  there's one shared BigQuery warehouse, not per-branch isolated datasets.
- Secrets set via `gh secret set` piped from local credential files —
  never typed into chat or committed.

## Reporting / BI

- Recommended **Looker Studio** (free, native BigQuery connector) over
  Looker proper (enterprise LookML platform) — a personal project with one
  dimension table doesn't need it.
