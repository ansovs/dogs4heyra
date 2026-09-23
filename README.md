# dogs4heyra

Extracts dog breed data from [The Dog API](https://api.thedogapi.com/v1/breeds).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

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
cp .dlt/secrets.toml.example .dlt/secrets.toml   # fill in your BigQuery service account
export DOG_API_KEY=your-key-here
dogs4heyra-load
```

This uses [dlt](https://dlthub.com) to load breed data into BigQuery's free
sandbox tier (no billing account required). See `.dlt/secrets.toml.example`
for setup steps (create a GCP project, a service account with BigQuery
Data Editor + Job User roles, and a JSON key).

Data lands in the `dog_breeds` dataset, table `breeds`. Override the
destination/dataset with `dogs4heyra-load --destination duckdb --dataset dog_breeds`
to load locally instead.

## Tests

```bash
pytest
```

The pipeline test loads sample data into a local DuckDB file — no
BigQuery credentials are needed to run the test suite.
