-- Audit trail for gold_breeds' row-level filtering: every silver_breeds
-- row that did NOT make it into gold_breeds, and why. Exists so
-- filtering never means data silently disappears -- see the
-- assert_gold_accounts_for_all_silver_rows test, which fails if any
-- silver row is missing from both this model and gold_breeds.
with silver as (

    select
        *,
        row_number() over (partition by breed_name order by id) as name_rank
    from {{ ref('silver_breeds') }}

),

flagged as (

    select
        id,
        breed_name,
        {{ breed_quality_issues() }} as exclusion_reasons
    from silver

)

select id, breed_name, exclusion_reasons
from flagged
where array_length(exclusion_reasons) > 0
