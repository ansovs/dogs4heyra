-- True bronze: raw, untouched, full append history. One row per
-- (breed, load) -- not deduplicated, no cleaning, no parsing. That work
-- belongs in silver; bronze exists so there's a materialized, queryable
-- mirror of raw without ever writing back to raw itself.
select * from {{ source('raw', 'breeds') }}
