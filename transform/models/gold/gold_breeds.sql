-- Dashboard-ready breed dimension: a curated, quality-filtered subset
-- of silver_breeds, materialized as a table (not a view) so BI tools
-- get consistent query performance without recomputing silver's window
-- functions on every dashboard load.
--
-- Row-level filtering (see the breed_quality_issues macro) means this
-- is NOT 1:1 with silver_breeds -- rows that fail the quality bar (or
-- are a duplicate breed_name) are left out. Nothing disappears
-- silently though: every excluded row, and why, is in
-- gold_breeds_excluded instead.
with silver as (

    select
        *,
        row_number() over (partition by breed_name order by id) as name_rank
    from {{ ref('silver_breeds') }}

),

qualified as (

    select *
    from silver
    where array_length({{ breed_quality_issues() }}) = 0

)

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

from qualified
