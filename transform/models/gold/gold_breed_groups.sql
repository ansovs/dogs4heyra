{#
  breed_group in the API sometimes packs multiple memberships into one
  string ("Sighthound & Pariah", "Spitz and Primitive Types") or uses
  regional/spelling variants of a single group ("Pastoral/Herding" -- UK
  "Pastoral" vs US/AKC "Herding" naming for the same group; "Scent
  Hound" vs "Scenthound" is just spacing). Splitting on &, /, and "and"
  handles both the same way: a breed with a compound value shows up
  under every resulting group here instead of picking one and losing
  the rest -- correct for genuine dual membership, and harmless for
  same-group alternate naming (the breed is just filterable under
  either name then).
#}

select distinct
    breed_id,
    breed_name,
    {{ normalize_breed_group_token('raw_token') }} as breed_group

from (
    select
        breed_id,
        breed_name,
        token as raw_token
    from {{ ref('gold_breeds') }},
    unnest(split(regexp_replace(breed_group, r'(?i)\s*(?:&|/|\band\b)\s*', '|'), '|')) as token
)
