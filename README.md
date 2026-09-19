# Feed Concierge

A personal, static "concierge feed". A GitHub Actions job fetches articles from configured
sources (Hacker News, Lobsters, LWN.net, Phoronix), asks [TypeSafe Jev](https://docs.typesafe.ai/) a few
typed questions about each new article, combines the answers with freshness in plain Ruby,
and publishes the ranked list to GitHub Pages.

## How ranking works

For every article Jev answers four questions in one request
(see `lib/feed_concierge/judge.rb`), with the reader profile from `config/profile.md` in the state:

| id | type | meaning |
| --- | --- | --- |
| `interest` | Score 0–4 | how well the article matches the profile |
| `substance` | Score 0–3 | how substantive the content looks |
| `worth_reading` | Noul | probability the reader would be glad they opened it |
| `evergreen` | Noul | probability it is still worth reading in a month |

Code owns the rest (`lib/feed_concierge/ranker.rb`, weights in `config/settings.yml`):

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
export TYPESAFE_AI_API_KEY=...
bin/build            # fetch feeds, judge new articles, write site/index.html
bin/rerank           # rebuild the page from the cache with current weights
FEED_CONCIERGE_FAKE_JEV=1 bin/build   # dry run without an API key
```

## Deploying

1. Push to GitHub and set repository secret `TYPESAFE_AI_API_KEY`.
2. Settings → Pages → Source: **GitHub Actions**.
3. Run the "Build and publish" workflow once manually; afterwards it runs on the cron schedule.

The judgment cache lives in the Actions cache (`actions/cache`). If it is evicted the next
run simply re-judges the current feed, which costs well under a cent.

## Sources

Configured under `sources:` in `config/settings.yml`. Three source types exist:

| type | what it reads | extra metadata |
| --- | --- | --- |
| `hacker_news` | hnrss.org feeds | points, comment count, comments link |
| `lobsters` | lobste.rs JSON endpoints | score, tags, comment count, comments link |
| `rss` | any RSS feed (`name:` + `feeds:`), used for LWN.net and Phoronix | feed description as summary |
| `redmine` | tickets with recent activity on a Redmine tracker (bugs.ruby-lang.org) | tracker, status, top description; last activity time as publication time |

The same link submitted to several aggregators is judged once; the first source in config
order wins. Set `excerpt: false` on a source to judge from feed data only, without fetching
the linked page. To add a new type, write a class under `lib/feed_concierge/sources/` that
returns `Article` structs from `#articles`, register it in `lib/feed_concierge/sources.rb`,
and prefix article ids with the source name so they stay globally unique.

## Tuning

- `config/profile.md`: describe what you like and dislike. This is the "prompt".
- `config/settings.yml`: sources, weights, freshness half-life, exposure decay, top N, per-source caps.
- `lib/feed_concierge/judge.rb`: question wording and Score levels. Jev reads literally, so
  describe concrete situations per level rather than degrees.
