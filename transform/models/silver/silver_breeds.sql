-- Clean passthrough for now -- no silver-specific logic yet. Exists so
-- downstream models/consumers have a stable silver interface to build
-- against as real conformance/enrichment logic gets added here later.
select * from {{ ref('bronze_breeds') }}
