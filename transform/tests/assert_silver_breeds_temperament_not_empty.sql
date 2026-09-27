-- dbt test: passes if this returns zero rows. Every breed currently has
-- at least one temperament trait; an empty array here would silently
-- break good_for_families/good_for_apartments (both key off this list).
select id, breed_name
from {{ ref('silver_breeds') }}
where temperament_list is null or array_length(temperament_list) = 0
