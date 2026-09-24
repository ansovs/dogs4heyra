with source as (

    select * from {{ source('raw', 'breeds') }}

),

renamed as (

    select
        id,
        name as breed_name,
        breed_group,
        origin,
        country_code,
        description,
        history,
        temperament,
        split(trim(temperament), ', ') as temperament_list,

        life_span,
        safe_cast({{ extract_min_number('life_span') }} as int64) as life_span_min_years,
        safe_cast({{ extract_max_number('life_span') }} as int64) as life_span_max_years,

        weight__imperial as weight_imperial,
        weight__metric as weight_metric,
        {{ extract_min_number('weight__metric') }} as weight_metric_min_kg,
        {{ extract_max_number('weight__metric') }} as weight_metric_max_kg,

        height__imperial as height_imperial,
        height__metric as height_metric,
        {{ extract_min_number('height__metric') }} as height_metric_min_cm,
        {{ extract_max_number('height__metric') }} as height_metric_max_cm,

        image__url as image_url,

        _dlt_load_id as load_id,
        _dlt_id as raw_row_id

    from source
    -- Belt-and-suspenders, not a fix for anything observed: the source
    -- test on raw.breeds.name (sources.yml) is what actually catches a
    -- null name loudly, in CI, before it ever reaches this filter. This
    -- WHERE just keeps such a row out of the current-state model rather
    -- than passing a half-populated breed downstream once that test has
    -- already failed and someone's looking at it.
    where name is not null

)

select * from renamed
