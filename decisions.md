# Decisions

Quick log of what I chose, why, and what I cut. Those are listed at the bottom.

## Setup

- Venv is `.venv.nosync`, not `.venv`. The project lives under an iCloud-synced Desktop, and iCloud kept re-hiding pip's editable-install file, which silently broke imports. Renaming was easier than moving the project.
- GitHub repo is private.

## Loading

- **dlt into BigQuery sandbox.** It's free, needs no billing account, and the data is queryable with plain SQL.
- **`append`, not `replace`.** Raw keeps the full history of every run, so the silver layer has something to collapse. Fine for this project would reconsider for larger projects / datasets.
- **Daily run via GitHub Actions cron at 02:00 UTC**, literally UTC, not Copenhagen time. 

## Warehouse: bronze / silver / gold

One BigQuery dataset per layer.

- **Bronze:** untouched raw copy.
- **Silver:** one row per breed, current state. The collapse is per column, so the latest non-null value wins for each field independently. A null in today's load can't wipe out a real value from an earlier run.
- **Gold:** cleaned, filtered, ready for the dashboard. It is not just a copy of silver. Rows that fail sanity checks, or duplicate a breed name, are excluded, and every excluded row and its reason go into `gold_breeds_excluded`. A test checks that each silver row lands in exactly one of the two, so nothing disappears quietly.

Modeling choices:
- `id` stays a string. It's an identifier, not a number.
- Life span, weight and height are free text ("Male: X-Y; Female: A-B", decimals, etc.), so I pull out every number in the string and take min/max, instead of a fixed pattern that would break on the odd formats.
- Temperaments are lowercased, trimmed and deduplicated. "Alert" vs "alert" was inflating the trait count.
- `breed_group` values like "Sighthound & Pariah" are split into multiple memberships instead of forced into one, so a breed with two groups shows up under both.
- Bridge tables for temperaments and groups, plus one wide `gold_breed_attributes` table, because separate tables don't cross-filter in most BI tools. Only charts on the same data source do.

## Tests

- Thresholds come from the actual data (e.g. life span bounds set after seeing the real 5-18 year spread), not guesses.
- Failures that gold guarantees by construction are errors. Known upstream messiness, like duplicate breed names in silver, only warns.
- Every filter or dedup step has a reconciliation test, so row counts add up exactly.

## CI/CD

- Two jobs: `pytest` on every push and PR (no credentials needed), and `dbt build` on pushes to `main` only.
- Secrets went in with `gh secret set` from local files. They were never typed into chat or committed.

## Dashboard

Looker Studio: free, and it connects to BigQuery directly.


## Time constraints and what I skipped

- **No dev/prod split.** The case asks for both targets, but I have one shared BigQuery warehouse, so `dbt build` runs on `main` only and PRs don't build the models. With more time: separate dev and prod datasets, with dbt running on PRs against dev.
- **[Anything else you cut, e.g. incremental models, alerting on failed runs, dashboard polish, a README narrative, and why.]**
- **What I'd do next:** [1-3 concrete items, e.g. dev/prod targets, failure notifications, checking the heuristic flags against an outside source.]