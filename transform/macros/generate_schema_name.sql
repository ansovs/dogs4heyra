{#
  dbt's default generate_schema_name concatenates the profile's target
  schema with a model's +schema config (e.g. "dog_breeds_staging_bronze").
  Override it so +schema is used as the literal dataset name instead --
  each medallion layer (bronze/silver/gold) gets its own clean dataset.

  Also makes the resulting dataset target-aware: the `prod` target (used
  only by the daily-load workflow) writes to the real datasets exactly
  as named; every other target (the `dev` default -- used locally and by
  CI on every push/PR) gets a `_dev` suffix, so CI and ad hoc local runs
  can never write to the same tables the real pipeline and any dashboard
  built on it depend on. Sources are unaffected either way -- `dev` runs
  still read the real, current `raw.breeds` (harmless; only writes are
  isolated), so CI is testing against real data, just not writing into
  it.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set base_schema = custom_schema_name | trim if custom_schema_name is not none else target.schema -%}
    {%- if target.name == 'prod' -%}
        {{ base_schema }}
    {%- else -%}
        {{ base_schema }}_dev
    {%- endif -%}
{%- endmacro %}
