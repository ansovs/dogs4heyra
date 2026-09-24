with source as (

    select * from {{ source('raw', 'breeds') }}

),

renamed as (

    select
        safe_cast(id as int64) as breed_id,
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

)

select * from renamed
