{#
  Single source of truth for gold's row-level quality bar. Used both to
  filter gold_breeds (array_length(...) = 0) and to populate
  gold_breeds_excluded (array_length(...) > 0) -- so the filter and its
  audit trail can never drift apart. Mirrors the conditions checked by
  transform/tests/assert_silver_breeds_reasonable_*.sql and
  assert_silver_breeds_temperament_not_empty.sql; update both places
  together if the quality bar changes.

  Expects `name_rank` (row_number() partitioned by breed_name, ordered by
  id) and silver_breeds' other columns to already be in scope.
#}

{% macro breed_quality_issues() %}
    array(
        select reason from unnest([
            case when temperament_list is null or array_length(temperament_list) = 0
                 then 'empty temperament_list' end,
            case when life_span_min_years is not null and life_span_min_years not between 1 and 25
                 then 'life_span_min_years out of range' end,
            case when life_span_max_years is not null and life_span_max_years not between 1 and 25
                 then 'life_span_max_years out of range' end,
            case when life_span_min_years is not null and life_span_max_years is not null
                      and life_span_min_years > life_span_max_years
                 then 'life_span_min_years > life_span_max_years' end,
            case when weight_metric_min_kg is not null and weight_metric_min_kg <= 0
                 then 'weight_metric_min_kg <= 0' end,
            case when weight_metric_max_kg is not null and weight_metric_max_kg <= 0
                 then 'weight_metric_max_kg <= 0' end,
            case when weight_metric_min_kg is not null and weight_metric_max_kg is not null
                      and weight_metric_min_kg > weight_metric_max_kg
                 then 'weight_metric_min_kg > weight_metric_max_kg' end,
            case when height_metric_min_cm is not null and height_metric_min_cm <= 0
                 then 'height_metric_min_cm <= 0' end,
            case when height_metric_max_cm is not null and height_metric_max_cm <= 0
                 then 'height_metric_max_cm <= 0' end,
            case when height_metric_min_cm is not null and height_metric_max_cm is not null
                      and height_metric_min_cm > height_metric_max_cm
                 then 'height_metric_min_cm > height_metric_max_cm' end,
            case when name_rank > 1
                 then 'duplicate breed_name (kept one row, string-order tie-break on id)' end
        ]) as reason
        where reason is not null
    )
{% endmacro %}
