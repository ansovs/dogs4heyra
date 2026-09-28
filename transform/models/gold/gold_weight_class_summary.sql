-- One row per weight class: breed count, and the average of each
-- breed's own weight_metric_avg_kg/life_span_avg_years (each already the
-- midpoint of that breed's min/max -- see silver_breeds). Averaging
-- per-breed averages here is mathematically the same as averaging the
-- raw min/max pairs directly, just without recomputing the midpoint
-- formula a second time.
select
    {{ weight_class('weight_metric_max_kg') }} as weight_class,
    count(*) as num_breeds,
    round(100 * count(*) / sum(count(*)) over (), 1) as pct_of_total,
    round(avg(weight_metric_avg_kg), 1) as avg_weight_kg,
    round(avg(life_span_avg_years), 1) as avg_life_span_years
from {{ ref('gold_breeds') }}
group by weight_class
-- Small -> Giant, with Unknown (null weight) last regardless of
-- BigQuery's default null ordering.
order by min(weight_metric_max_kg) is null, min(weight_metric_max_kg)
