-- dbt test: passes if this returns zero rows. Every silver_breeds id
-- must end up in exactly one of gold_breeds or gold_breeds_excluded --
-- filtering in gold_breeds.sql should never silently lose a row (or
-- double-count one).
with silver_ids as (

    select id from {{ ref('silver_breeds') }}

),

accounted as (

    select breed_id as id from {{ ref('gold_breeds') }}
    union all
    select id from {{ ref('gold_breeds_excluded') }}

)

select s.id, count(a.id) as times_accounted_for
from silver_ids s
left join accounted a using (id)
group by s.id
having count(a.id) != 1
