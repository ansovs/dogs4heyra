-- dbt test: passes if this returns zero rows. Weight/height should be
-- positive and min <= max -- guards against a parsing regression in
-- extract_min_number/extract_max_number, not anything observed today.
select
    id, breed_name,
    weight_metric, weight_metric_min_kg, weight_metric_max_kg,
    height_metric, height_metric_min_cm, height_metric_max_cm
from {{ ref('silver_breeds') }}
where
    (weight_metric_min_kg is not null and weight_metric_min_kg <= 0)
    or (weight_metric_max_kg is not null and weight_metric_max_kg <= 0)
    or (
        weight_metric_min_kg is not null and weight_metric_max_kg is not null
        and weight_metric_min_kg > weight_metric_max_kg
    )
    or (height_metric_min_cm is not null and height_metric_min_cm <= 0)
    or (height_metric_max_cm is not null and height_metric_max_cm <= 0)
    or (
        height_metric_min_cm is not null and height_metric_max_cm is not null
        and height_metric_min_cm > height_metric_max_cm
    )
