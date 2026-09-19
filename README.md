# Feed Concierge

A personal, static "concierge feed". A cron job fetches articles from configured sources,
asks [TypeSafe Jev](https://docs.typesafe.ai/) a few typed questions about each new article,
and publishes the ranked list to GitHub Pages.

## How ranking works

Every article is judged once by Jev with a question set chosen per source
(`questions:` in `config/settings.yml`, see `lib/feed_concierge/judge.rb`). The reader
profile from `config/profile.md` is part of the state.

Every request also carries one Noul per tag in `config/tags.yml`.
Tags whose probability clears `tags.min_probability` are shown on the page, at most
`tags.max_per_article` per article. Bump `Judge::VERSION` after changing questions to re-judge
cached articles, or bump one entry of `Judge::SET_VERSIONS` to re-judge only the sources using that set.

Code owns the rest (`lib/feed_concierge/ranker.rb`, weights in `config/settings.yml`):

```
relevance = Σ weights[set][q] * normalized(q)     # score/max, noul as is, choice = Σ p(option) * choice_weights
freshness = floor + (1 - floor) / (1 + (age_hours / half_life)^steepness)   # half_life grows with evergreen
exposure  = 0.5 ^ (days since first shown on the page / exposure_half_life_days)
score     = relevance * freshness * exposure
```

The page lists every article with `score >= min_score`, newest-scored first, up to `top_n`.

Judgments are cached in `data/scores.json` for `retention_days`, so each article costs one Jev
request per retention window; after that it is forgotten and its exposure resets.
Changing weights only needs `bin/regenerate`. Open the page with `?debug=1` (linked in the footer)
to see each article's score breakdown, loaded from `data.json`.

## Running locally

```sh
bundle install
# Export TYPESAFE_AI_API_KEY using tools such as `op run` or `envchain`.
bin/build       # fetch feeds, judge new articles, write site/index.html
bin/regenerate  # rebuild the page from the cache with current weights

FEED_CONCIERGE_FAKE_JEV=1 bin/build  # dry run without an API key
```

## Tuning

- `config/profile.md`: describe what you like and dislike. This is the "prompt".
- `config/settings.yml`: sources, weights, freshness half-life, exposure half-life, retention, score threshold and cap, per-source caps.
- `lib/feed_concierge/judge.rb`: question wording and Score levels. Jev reads literally, so describe concrete situations per level rather than degrees.
