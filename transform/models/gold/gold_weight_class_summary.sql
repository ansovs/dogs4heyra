-- One row per weight class: breed count, average weight, and average
-- predicted life span. "Predicted life span" = midpoint of
-- life_span_min_years/life_span_max_years, same convention used
-- throughout (e.g. the README's "longest predicted life span" answer).
select
    {{ weight_class('weight_metric_max_kg') }} as weight_class,
    count(*) as num_breeds,
    round(100 * count(*) / sum(count(*)) over (), 1) as pct_of_total,
    round(avg((weight_metric_min_kg + weight_metric_max_kg) / 2), 1) as avg_weight_kg,
    round(avg((life_span_min_years + life_span_max_years) / 2), 1) as avg_life_span_years
from {{ ref('gold_breeds') }}
group by weight_class
-- Small -> Giant, with Unknown (null weight) last regardless of
-- BigQuery's default null ordering.
order by min(weight_metric_max_kg) is null, min(weight_metric_max_kg)
