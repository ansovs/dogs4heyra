-- dbt test: passes if this returns zero rows. gold_breed_attributes is
-- a cross join of each breed's groups x traits, so its row count is not
-- meaningful as a breed count -- but the join must never drop or add a
-- breed, only multiply its rows. Distinct breed_id count here must
-- always equal gold_breeds' row count exactly.
with counts as (
    select
        (select count(distinct breed_id) from {{ ref('gold_breed_attributes') }}) as attr_breeds,
        (select count(*) from {{ ref('gold_breeds') }}) as gold_breeds_count
)

select * from counts where attr_breeds != gold_breeds_count
