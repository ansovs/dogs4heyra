"""Load dog breed data into a warehouse using dlt.

Defaults to BigQuery (free sandbox tier). Credentials are read from
.dlt/secrets.toml (see .dlt/secrets.toml.example) or the standard
dlt/BigQuery environment variables.
"""

from __future__ import annotations

import argparse
import os

import dlt

from dogs4heyra.extract import fetch_breeds


@dlt.resource(name="breeds", write_disposition="replace")
def breeds_resource(api_key: str | None = None):
    yield fetch_breeds(api_key=api_key)


def run(
    destination: str = "bigquery",
    dataset_name: str = "dog_breeds",
    api_key: str | None = None,
):
    pipeline = dlt.pipeline(
        pipeline_name="dogs4heyra",
        destination=destination,
        dataset_name=dataset_name,
    )
    load_info = pipeline.run(breeds_resource(api_key=api_key))
    print(load_info)
    return load_info


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--destination", default="bigquery", help="dlt destination (default: bigquery)"
    )
    parser.add_argument(
        "--dataset", default="dog_breeds", help="Target dataset name (default: dog_breeds)"
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("DOG_API_KEY"),
        help="The Dog API key (defaults to the DOG_API_KEY env var)",
    )
    args = parser.parse_args(argv)

    run(destination=args.destination, dataset_name=args.dataset, api_key=args.api_key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
