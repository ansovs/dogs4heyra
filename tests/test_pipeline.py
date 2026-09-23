from unittest.mock import patch

import dlt

from dogs4heyra.pipeline import breeds_resource

SAMPLE_BREEDS = [
    {
        "id": 1,
        "name": "Affenpinscher",
        "breed_group": "Toy",
        "temperament": "Stubborn, Curious, Playful",
        "life_span": "10 - 12 years",
        "weight": {"imperial": "6 - 13", "metric": "3 - 6"},
    }
]


def test_breeds_resource_loads_into_duckdb(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    with patch("dogs4heyra.pipeline.fetch_breeds", return_value=SAMPLE_BREEDS):
        pipeline = dlt.pipeline(
            pipeline_name="test_dogs4heyra",
            destination="duckdb",
            dataset_name="dog_breeds",
        )
        load_info = pipeline.run(breeds_resource())

    assert not load_info.has_failed_jobs

    with pipeline.sql_client() as client:
        rows = client.execute_sql("SELECT name, breed_group FROM breeds")

    assert rows == [("Affenpinscher", "Toy")]
