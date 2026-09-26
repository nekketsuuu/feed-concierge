# frozen_string_literal: true

require_relative "sources/http"
require_relative "sources/hacker_news"
require_relative "sources/lobsters"
require_relative "sources/rss"
require_relative "sources/aws_whats_new"
require_relative "sources/redmine"
require_relative "sources/github_pulls"
require_relative "sources/jpcert_weekly"
require_relative "sources/cisa_kev"
require_relative "sources/github_advisories"
require_relative "sources/listing"
require_relative "sources/feed_links"
require_relative "sources/github_releases"

module FeedConcierge
  module Sources
    REGISTRY = { "hacker_news" => HackerNews, "lobsters" => Lobsters, "rss" => Rss, "aws_whats_new" => AwsWhatsNew,
                 "redmine" => Redmine,
                 "github_pulls" => GithubPulls, "jpcert_weekly" => JpcertWeekly, "cisa_kev" => CisaKev,
                 "github_advisories" => GithubAdvisories, "listing" => Listing,
                 "feed_links" => FeedLinks, "github_releases" => GithubReleases }.freeze
    NON_CONSTRUCTOR_KEYS = %w[type excerpt questions].freeze

    # Builds sources from config/settings.yml entries like:
    #   - type: hacker_news
    #     min_points: 30
    # Sources that ask Jev while fetching (release titling) also receive the client and a
    # predicate for articles the store already holds.
    def self.build(configs, client: nil, known: ->(_id) { false })
      configs.map do |cfg|
        klass = REGISTRY.fetch(cfg.fetch("type")) { raise ArgumentError, "unknown source type: #{cfg['type']}" }
        args = cfg.except(*NON_CONSTRUCTOR_KEYS).transform_keys(&:to_sym)
        args.merge!(client: client, known: known) if klass.instance_method(:initialize).parameters.any? { |_, n| n == :client }
        klass.new(**args)
      end
    end

    # Source names (Article#source) whose config sets `excerpt: false`.
    def self.without_excerpt(configs)
      configs.reject { |cfg| cfg.fetch("excerpt", true) }.map { |cfg| cfg["name"] || cfg["type"] }
    end

    # Source name -> Judge question set name (config `questions:`, default "default").
    def self.question_sets(configs)
      configs.to_h { |cfg| [cfg["name"] || cfg["type"], cfg.fetch("questions", "default")] }
    end

    # Sources are fetched in config order; when several list the same link, the first wins.
    # A broken source is logged and skipped so the rest of the build still runs.
    def self.fetch_all(configs, logger: $stderr, client: nil, known: ->(_id) { false })
      articles = build(configs, client: client, known: known).flat_map do |source|
        source.articles
      rescue FetchError, JevClient::Error, RSS::Error, JSON::ParserError, SystemCallError, Timeout::Error => e
        logger.puts "source #{source.class.name.split('::').last} failed: #{e.message[0, 200]}"
        []
      end
      articles.uniq(&:id).uniq(&:canonical_url)
    end
  end
end
