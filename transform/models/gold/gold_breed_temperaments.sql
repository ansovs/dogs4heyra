-- Bridge table: one row per (breed, temperament trait) pair. Exists so
-- any BI tool can filter/group on trait with a plain WHERE clause --
-- temperament_list in gold_breeds is a BigQuery REPEATED/ARRAY field,
-- and most no-code BI tools' native BigQuery connectors (confirmed for
-- Looker Studio) don't handle those cleanly, tending to silently
-- flatten one row per array element and multiply breed counts on any
-- chart that touches it.
select
    breed_id,
    breed_name,
    trait
from {{ ref('gold_breeds') }},
unnest(temperament_list) as trait
