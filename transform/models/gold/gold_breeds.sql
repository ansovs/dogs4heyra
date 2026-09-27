-- Dashboard-ready breed dimension: a curated, business-friendly subset
-- of silver_breeds, materialized as a table (not a view) so BI tools
-- get consistent query performance without recomputing silver's window
-- functions on every dashboard load.
select
    id as breed_id,
    breed_name,
    breed_group,
    species_id,

    life_span_min_years,
    life_span_max_years,
    weight_metric_min_kg,
    weight_metric_max_kg,
    height_metric_min_cm,
    height_metric_max_cm,

    temperament_list,
    good_for_families,
    good_for_apartments,

    image_url

from {{ ref('silver_breeds') }}
