{#
  Buckets a max-weight-in-kg column into size classes. Boundaries are the
  same ones used in the README's "Example analysis" section -- kept here
  as a macro so gold_weight_class_summary.sql (and anything else that
  wants the same buckets later) can't drift from that write-up.
#}

{% macro weight_class(weight_max_kg_column) %}
    case
        when {{ weight_max_kg_column }} is null then 'Unknown'
        when {{ weight_max_kg_column }} <= 10 then 'Small (<=10kg)'
        when {{ weight_max_kg_column }} <= 25 then 'Medium (10-25kg)'
        when {{ weight_max_kg_column }} <= 45 then 'Large (25-45kg)'
        else 'Giant (>45kg)'
    end
{% endmacro %}
