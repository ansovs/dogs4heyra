-- Clean passthrough for now -- no gold-specific logic yet. Exists so
-- downstream consumers (BI tools, dashboards) have a stable gold
-- interface to build against as real aggregation/presentation logic
-- gets added here later.
select * from {{ ref('silver_breeds') }}
