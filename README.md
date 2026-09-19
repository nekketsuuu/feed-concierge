# Feed Concierge

A personal, static "concierge feed". A GitHub Actions job fetches articles from configured
sources (Hacker News, Lobsters, LWN.net, Phoronix), asks [TypeSafe Jev](https://docs.typesafe.ai/) a few
typed questions about each new article, combines the answers with freshness in plain Ruby,
and publishes the ranked list to GitHub Pages.

## How ranking works

Every article is judged once by Jev with a *question set* chosen per source
(`questions:` in `config/settings.yml`, see `lib/feed_concierge/judge.rb`). The reader
profile from `config/profile.md` is part of the state.

`default` (articles):

| id | type | meaning |
| --- | --- | --- |
| `interest` | Score 0–4 | how well the article matches the profile |
| `substance` | Score 0–3 | how substantive the content looks |
| `worth_reading` | Noul | probability the reader would be glad they opened it |
| `evergreen` | Noul | probability it is still worth reading in a month |

`changelog` (product changelogs) replaces `substance` with a `change_kind` Choice: new_capability /
breaking_or_deprecation / pricing_or_limits / incremental_improvement / regional_availability / fix_or_maintenance.

`pull_request` (merged PRs) uses a `pr_kind` Choice (new_feature / behavior_change_or_deprecation /
performance / bug_fix / internal_refactor / docs_tests_ci) plus `user_impact`, `interest`, `worth_reading`, `evergreen`.

`ticket` (issue trackers such as bugs.ruby-lang.org):

| id | type | meaning |
| --- | --- | --- |
| `kind` | Choice | language_change / design_discussion / behavior_bug / crash_report / build_platform / housekeeping |
| `user_impact` | Score 0–3 | how much of the user base would notice the change or defect |
| `interest`, `worth_reading`, `evergreen` | as above | |

Every request also carries one Noul per tag in `config/tags.yml` (a Lobsters-like vocabulary).
Tags whose probability clears `tags.min_probability` are shown on the page, at most
`tags.max_per_article` per article. Bump `Judge::VERSION` after changing questions to re-judge
cached articles.

Code owns the rest (`lib/feed_concierge/ranker.rb`, weights in `config/settings.yml`):

```
relevance = Σ weights[set][q] * normalized(q)     # score/max, noul as is, choice = Σ p(option) * choice_weights
freshness = floor + (1 - floor) * 2^(-age_hours / half_life)     # half_life grows with evergreen
exposure  = 0.5 ^ (days since first shown on the page / exposure_half_life_days)
score     = relevance * freshness * exposure
```

The page lists every article with `score >= min_score`, newest-scored first, up to `top_n`.

Judgments are cached in `data/scores.json` for `retention_days`, so each article costs one Jev
request per retention window; after that it is forgotten and its exposure resets.
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
| `cisa_kev` | CVEs added to CISA's Known Exploited Vulnerabilities catalog in the last N days | vendor, product, and CWEs as tags |
| `jpcert_weekly` | entries of the JPCERT/CC Weekly Report, one article per entry | entry body extracted from the weekly page |
| `github_pulls` | pull requests merged recently in one repository (rails/rails) | labels as tags, PR description, merge time as publication time; sends `GITHUB_TOKEN` when set |

piyolog, tl;dr sec, BleepingComputer, and the engineering blogs (Spotify, web.dev, Kubernetes,
RubyGems, 37signals, Evil Martians, Shopify, OpenTelemetry, Figma, Rails at Scale, Netflix, Sentry,
Martin Fowler, blog.jxck.io, AWS blogs, Tenderlove Making, rubyflow) are plain `rss` sources; the
source handles RSS 2.0, RSS 1.0, and Atom. Product changelogs (GitHub Changelog,
AWS What's New, Cloudflare, Fastly) use the `rss` type with
`questions: changelog` and `max_age_days:` to ignore old entries in large feeds.

The same link submitted to several aggregators is judged once; the first source in config
order wins. Set `excerpt: false` on a source to judge from feed data only, without fetching
the linked page. To add a new type, write a class under `lib/feed_concierge/sources/` that
returns `Article` structs from `#articles`, register it in `lib/feed_concierge/sources.rb`,
and prefix article ids with the source name so they stay globally unique.

## Tuning

- `config/profile.md`: describe what you like and dislike. This is the "prompt".
- `config/settings.yml`: sources, weights, freshness half-life, exposure half-life, retention, score threshold and cap, per-source caps.
- `lib/feed_concierge/judge.rb`: question wording and Score levels. Jev reads literally, so
  describe concrete situations per level rather than degrees.
