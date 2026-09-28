{#
  Single denormalized fact table -- one row per (breed, breed_group,
  temperament trait) combination -- meant to be the ONE data source
  every dashboard chart reads from. Cross-filtering between charts in
  most BI tools (confirmed for Looker Studio) only works reliably when
  they share the same data source: a "breeds by group" chart pointed at
  gold_breed_groups and a "top temperaments" chart pointed at
  gold_breed_temperaments will never filter each other on click, even
  though both trace back to the same breeds, because Looker Studio
  treats them as unrelated sources.

  CAUTION -- this bit matters, verified by getting it wrong myself while
  testing this table: this is a full cross join of each breed's groups x
  traits, so any row-count-based aggregation overcounts. COUNT(*),
  COUNTIF(good_for_apartments), or SUM of a boolean flag all count ROWS,
  and a breed appears once per trait here -- e.g. filtering to the Toy
  group and running COUNTIF(good_for_apartments) gave 59 against a
  filtered total of 28 breeds (more "true" rows than breeds!), because
  each apartment-friendly Toy breed's flag got counted once per trait it
  has. The correct form is COUNT(DISTINCT breed_id) / COUNT(DISTINCT
  CASE WHEN good_for_apartments THEN breed_id END) -- and in Looker
  Studio specifically, that means setting the field's aggregation to
  "Count Distinct", not the default "Count" or "Sum".
  assert_gold_breed_attributes_breed_count_matches checks that distinct
  breed_id count here still equals gold_breeds' row count (the join must
  never drop or add breeds, only multiply their rows) -- but that test
  can't catch the wrong-aggregation-in-a-chart mistake, only a human
  building the chart can.

  Practical guidance: use gold_breeds (no fan-out) for breed-level
  scorecards like "% good_for_families overall". Reach for this table
  only when a chart actually needs to slice by breed_group or trait, and
  set every count/percentage metric to distinct-breed aggregation when
  you do.
#}

select
    b.breed_id,
    b.breed_name,
    g.breed_group,
    t.trait,
    {{ weight_class('b.weight_metric_max_kg') }} as weight_class,
    b.species_id,
    b.life_span_min_years,
    b.life_span_max_years,
    b.life_span_avg_years,
    b.weight_metric_min_kg,
    b.weight_metric_max_kg,
    b.weight_metric_avg_kg,
    b.height_metric_min_cm,
    b.height_metric_max_cm,
    b.good_for_families,
    b.good_for_apartments,
    b.image_url

from {{ ref('gold_breeds') }} b
join {{ ref('gold_breed_groups') }} g on g.breed_id = b.breed_id
join {{ ref('gold_breed_temperaments') }} t on t.breed_id = b.breed_id
