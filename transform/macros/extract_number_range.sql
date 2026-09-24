{#
  The API's numeric fields (weight, height, life span) are free text and
  inconsistently formatted — plain ranges ("23-25"), gender-split ranges
  ("Male: 25-30; Female: 20-25"), and decimals ("3.2-4.5") all appear in
  the same column. Pulling every number out and taking min/max handles
  all of these instead of assuming one fixed pattern.
#}

{% macro extract_min_number(column_name) %}
    (select min(safe_cast(x as float64))
     from unnest(regexp_extract_all({{ column_name }}, r'\d+(?:\.\d+)?')) as x)
{% endmacro %}

{% macro extract_max_number(column_name) %}
    (select max(safe_cast(x as float64))
     from unnest(regexp_extract_all({{ column_name }}, r'\d+(?:\.\d+)?')) as x)
{% endmacro %}
