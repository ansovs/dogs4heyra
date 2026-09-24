"""Print `export VAR=value` lines for the BigQuery env vars dbt's profiles.yml needs.

Reads credentials already present in .dlt/secrets.toml so they don't need
to be re-entered. Usage:

    eval "$(.venv.nosync/bin/python scripts/print_bq_env.py)"
"""

import shlex
import tomllib

with open(".dlt/secrets.toml", "rb") as f:
    creds = tomllib.load(f)["destination"]["bigquery"]["credentials"]

for var, key in [
    ("BQ_PROJECT_ID", "project_id"),
    ("BQ_CLIENT_EMAIL", "client_email"),
    ("BQ_PRIVATE_KEY", "private_key"),
]:
    print(f"export {var}={shlex.quote(creds[key])}")
