{#
  dbt's default generate_schema_name concatenates the profile's target
  schema with a model's +schema config (e.g. "dog_breeds_staging_bronze").
  Override it so +schema is used as the literal dataset name instead --
  each medallion layer (bronze/silver/gold) gets its own clean dataset.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
