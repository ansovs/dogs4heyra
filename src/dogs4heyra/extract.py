"""Extract dog breed data from The Dog API (https://api.thedogapi.com/v1/breeds)."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from typing import Any

import requests

API_URL = "https://api.thedogapi.com/v1/breeds"
API_KEY_ENV_VAR = "DOG_API_KEY"

# Columns pulled out of nested fields for the CSV view.
CSV_FIELDS = [
    "id",
    "name",
    "breed_group",
    "bred_for",
    "temperament",
    "life_span",
    "weight_imperial",
    "weight_metric",
    "height_imperial",
    "height_metric",
    "image_url",
]


def fetch_breeds(api_key: str | None = None, timeout: float = 10.0) -> list[dict[str, Any]]:
    """Fetch the full list of breeds from The Dog API.

    Requires an API key; pass one via `api_key` or the DOG_API_KEY env var.
    Get a free key at https://thedogapi.com.
    """
    headers = {"x-api-key": api_key} if api_key else {}
    response = requests.get(API_URL, headers=headers, timeout=timeout)
    response.raise_for_status()
    return response.json()


def _flatten(breed: dict[str, Any]) -> dict[str, Any]:
    weight = breed.get("weight", {})
    height = breed.get("height", {})
    image = breed.get("image", {})
    return {
        "id": breed.get("id"),
        "name": breed.get("name"),
        "breed_group": breed.get("breed_group"),
        "bred_for": breed.get("bred_for"),
        "temperament": breed.get("temperament"),
        "life_span": breed.get("life_span"),
        "weight_imperial": weight.get("imperial"),
        "weight_metric": weight.get("metric"),
        "height_imperial": height.get("imperial"),
        "height_metric": height.get("metric"),
        "image_url": image.get("url"),
    }


def write_json(breeds: list[dict[str, Any]], path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(breeds, f, indent=2, ensure_ascii=False)


def write_csv(breeds: list[dict[str, Any]], path: str) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for breed in breeds:
            writer.writerow(_flatten(breed))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-o", "--output", default="breeds.json", help="Output file path (default: breeds.json)"
    )
    parser.add_argument(
        "-f",
        "--format",
        choices=["json", "csv"],
        default=None,
        help="Output format; inferred from the output file extension if omitted",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get(API_KEY_ENV_VAR),
        help=f"The Dog API key (defaults to the {API_KEY_ENV_VAR} env var)",
    )
    args = parser.parse_args(argv)

    fmt = args.format or ("csv" if args.output.lower().endswith(".csv") else "json")

    breeds = fetch_breeds(api_key=args.api_key)

    if fmt == "csv":
        write_csv(breeds, args.output)
    else:
        write_json(breeds, args.output)

    print(f"Wrote {len(breeds)} breeds to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
