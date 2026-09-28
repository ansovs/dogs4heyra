{#
  Folds pure spelling/spacing variants of the same group into one name.
  Distinct from splitting compound values (gold_breed_groups.sql) --
  these are single-group values that just aren't spelled consistently,
  confirmed by checking actual breed_group values live before adding
  each mapping (not guessed).
#}

{% macro normalize_breed_group_token(token_column) %}
    case trim({{ token_column }})
        when 'Mixed breed' then 'Mixed'
        when 'Scent Hound' then 'Scenthound'
        when 'Spitz-type' then 'Spitz'
        when 'Primitive Types' then 'Primitive'
        else trim({{ token_column }})
    end
{% endmacro %}
