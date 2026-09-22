import csv
import json

import responses

from dogs4heyra.extract import API_URL, fetch_breeds, write_csv, write_json

SAMPLE_BREEDS = [
    {
        "id": 1,
        "name": "Affenpinscher",
        "breed_group": "Toy",
        "bred_for": "Small rodent hunting, lapdog",
        "temperament": "Stubborn, Curious, Playful, Adventurous, Active, Fun-loving",
        "life_span": "10 - 12 years",
        "weight": {"imperial": "6 - 13", "metric": "3 - 6"},
        "height": {"imperial": "9 - 11.5", "metric": "23 - 29"},
        "image": {"url": "https://cdn2.thedogapi.com/images/BJa4kxc4X.jpg"},
    }
]


@responses.activate
def test_fetch_breeds_returns_parsed_json():
    responses.add(responses.GET, API_URL, json=SAMPLE_BREEDS, status=200)

    result = fetch_breeds()

    assert result == SAMPLE_BREEDS


@responses.activate
def test_fetch_breeds_sends_api_key_header():
    responses.add(responses.GET, API_URL, json=SAMPLE_BREEDS, status=200)

    fetch_breeds(api_key="secret")

    assert responses.calls[0].request.headers["x-api-key"] == "secret"


def test_write_json(tmp_path):
    path = tmp_path / "breeds.json"

    write_json(SAMPLE_BREEDS, str(path))

    assert json.loads(path.read_text()) == SAMPLE_BREEDS


def test_write_csv_flattens_nested_fields(tmp_path):
    path = tmp_path / "breeds.csv"

    write_csv(SAMPLE_BREEDS, str(path))

    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    assert rows[0]["name"] == "Affenpinscher"
    assert rows[0]["weight_imperial"] == "6 - 13"
    assert rows[0]["height_metric"] == "23 - 29"
    assert rows[0]["image_url"] == "https://cdn2.thedogapi.com/images/BJa4kxc4X.jpg"
