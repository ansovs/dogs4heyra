{#
  raw.breeds accumulates one full snapshot per dlt load (write_disposition
  is "append"), so the same breed id can appear in many rows over time.
  This collapses that history to a single current-state value per column:
  the most recent non-null value for that specific column, independently
  per column -- not just "take every column from the latest row", which
  would reintroduce nulls if the latest load happened to be missing a
  field that an earlier load had populated.
#}

{% macro last_non_null(column_name, partition_by='id', order_by='_dlt_load_id') %}
    last_value({{ column_name }} ignore nulls) over (
        partition by {{ partition_by }}
        order by {{ order_by }}
        rows between unbounded preceding and unbounded following
    )
{% endmacro %}
