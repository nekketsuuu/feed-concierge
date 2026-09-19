# HN Concierge

A personal, static "concierge feed" for Hacker News. A GitHub Actions job fetches the HN
RSS feeds every couple of hours, asks [TypeSafe Jev](https://docs.typesafe.ai/) a few typed
questions about each new article, combines the answers with freshness in plain Ruby, and
publishes the ranked list to GitHub Pages.

## How ranking works

For every article Jev answers four questions in one request
(see `lib/hn_concierge/judge.rb`), with the reader profile from `config/profile.md` in the state:

| id | type | meaning |
| --- | --- | --- |
| `interest` | Score 0–4 | how well the article matches the profile |
| `substance` | Score 0–3 | how substantive the content looks |
| `worth_reading` | Noul | probability the reader would be glad they opened it |
| `evergreen` | Noul | probability it is still worth reading in a month |

Code owns the rest (`lib/hn_concierge/ranker.rb`, weights in `config/settings.yml`):

```
relevance = 0.5 * interest/4 + 0.2 * substance/3 + 0.3 * worth_reading
freshness = floor + (1 - floor) * 2^(-age_hours / half_life)     # half_life grows with evergreen
exposure  = exposure_decay ^ (times already shown on the page)
score     = relevance * freshness * exposure
```

Judgments are cached in `data/scores.json`, so each article costs one Jev request ever.
Changing weights only needs `bin/rerank`.

## Running locally

```
bundle install
export TYPESAFE_API_KEY=...
bin/build            # fetch feeds, judge new articles, write site/index.html
bin/rerank           # rebuild the page from the cache with current weights
HN_CONCIERGE_FAKE_JEV=1 bin/build   # dry run without an API key
```

## Deploying

1. Push to GitHub and set repository secret `TYPESAFE_API_KEY`.
2. Settings → Pages → Source: **GitHub Actions**.
3. Run the "Build and publish" workflow once manually; afterwards it runs on the cron schedule.

The judgment cache lives in the Actions cache (`actions/cache`). If it is evicted the next
run simply re-judges the current feed, which costs well under a cent.

## Tuning

- `config/profile.md`: describe what you like and dislike. This is the "prompt".
- `config/settings.yml`: feeds, weights, freshness half-life, exposure decay, top N.
- `lib/hn_concierge/judge.rb`: question wording and Score levels. Jev reads literally, so
  describe concrete situations per level rather than degrees.
