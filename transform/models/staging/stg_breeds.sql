{% set raw_relation = source('raw', 'breeds') %}
{% set raw_columns = adapter.get_columns_in_relation(raw_relation) | map(attribute='name') | list %}
{% set has_perfect_for = 'perfect_for' in raw_columns %}

with source as (

    select * from {{ raw_relation }}

),

merged as (

    -- One row per (id, load) still, but every column now holds the most
    -- recent non-null value for that breed across all of raw's history,
    -- not just this row's own value.
    select
        id,
        {{ last_non_null('name') }} as name,
        {{ last_non_null('breed_group') }} as breed_group,
        {{ last_non_null('species_id') }} as species_id,
        {{ last_non_null('origin') }} as origin,
        {{ last_non_null('country_code') }} as country_code,
        {{ last_non_null('description') }} as description,
        {{ last_non_null('history') }} as history,
        {{ last_non_null('temperament') }} as temperament,
        {{ last_non_null('life_span') }} as life_span,
        {{ last_non_null('weight__imperial') }} as weight_imperial,
        {{ last_non_null('weight__metric') }} as weight_metric,
        {{ last_non_null('height__imperial') }} as height_imperial,
        {{ last_non_null('height__metric') }} as height_metric,
        {{ last_non_null('image__url') }} as image_url,
        {% if has_perfect_for -%}
        {{ last_non_null('perfect_for') }} as perfect_for,
        {%- else -%}
        cast(null as string) as perfect_for,  -- not yet populated by any raw load
        {%- endif %}
        _dlt_load_id as load_id,
        _dlt_id as raw_row_id

    from source

    qualify row_number() over (partition by id order by _dlt_load_id desc) = 1

),

renamed as (

    select
        id,
        name as breed_name,
        breed_group,
        species_id,
        origin,
        country_code,
        description,
        history,
        perfect_for,
        temperament,
        -- Source casing is inconsistent ("Alert" vs "alert" across
        -- breeds) -- lowercase + trim each trait so the same trait
        -- collapses to one value instead of two.
        array(
            select distinct trim(lower(trait))
            from unnest(split(trim(temperament), ', ')) as trait
        ) as temperament_list,

        life_span,
        safe_cast({{ extract_min_number('life_span') }} as int64) as life_span_min_years,
        safe_cast({{ extract_max_number('life_span') }} as int64) as life_span_max_years,

        weight_imperial,
        weight_metric,
        {{ extract_min_number('weight_metric') }} as weight_metric_min_kg,
        {{ extract_max_number('weight_metric') }} as weight_metric_max_kg,

        height_imperial,
        height_metric,
        {{ extract_min_number('height_metric') }} as height_metric_min_cm,
        {{ extract_max_number('height_metric') }} as height_metric_max_cm,

        image_url,

        load_id,
        raw_row_id

    from merged
    -- Belt-and-suspenders, not a fix for anything observed: the source
    -- test on raw.breeds.name (sources.yml) is what actually catches a
    -- null name loudly, in CI, before it ever reaches this filter. This
    -- WHERE just keeps such a row out of the current-state model rather
    -- than passing a half-populated breed downstream once that test has
    -- already failed and someone's looking at it.
    where name is not null

)

select * from renamed
