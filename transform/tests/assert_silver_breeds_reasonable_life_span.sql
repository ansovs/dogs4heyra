-- dbt test: passes if this returns zero rows.
-- Actual parsed data currently ranges 5-18 years; 1-25 gives headroom
-- for real variation while still catching a parsing regression or a
-- genuinely nonsensical source value (zero, negative, three-digit).
select id, breed_name, life_span, life_span_min_years, life_span_max_years
from {{ ref('silver_breeds') }}
where
    (life_span_min_years is not null and (life_span_min_years < 1 or life_span_min_years > 25))
    or (life_span_max_years is not null and (life_span_max_years < 1 or life_span_max_years > 25))
    or (
        life_span_min_years is not null and life_span_max_years is not null
        and life_span_min_years > life_span_max_years
    )
