require_relative "sources/http"
require_relative "sources/hacker_news"
require_relative "sources/lobsters"
require_relative "sources/rss"
require_relative "sources/redmine"

module FeedConcierge
  module Sources
    REGISTRY = { "hacker_news" => HackerNews, "lobsters" => Lobsters, "rss" => Rss, "redmine" => Redmine }.freeze
    NON_CONSTRUCTOR_KEYS = %w[type excerpt].freeze

    # Builds sources from config/settings.yml entries like:
    #   - type: hacker_news
    #     feeds: [https://hnrss.org/frontpage]
    def self.build(configs)
      configs.map do |cfg|
        klass = REGISTRY.fetch(cfg.fetch("type")) { raise ArgumentError, "unknown source type: #{cfg["type"]}" }
        klass.new(**cfg.except(*NON_CONSTRUCTOR_KEYS).transform_keys(&:to_sym))
      end
    end

    # Source names (Article#source) whose config sets `excerpt: false`.
    def self.without_excerpt(configs)
      configs.reject { |cfg| cfg.fetch("excerpt", true) }.map { |cfg| cfg["name"] || cfg["type"] }
    end

    # Sources are fetched in config order; when several list the same link, the first wins.
    # A broken source is logged and skipped so the rest of the build still runs.
    def self.fetch_all(configs, logger: $stderr)
      articles = build(configs).flat_map do |source|
        source.articles
      rescue FetchError, RSS::Error, JSON::ParserError, SystemCallError, Timeout::Error => e
        logger.puts "source #{source.class.name.split("::").last} failed: #{e.message[0, 200]}"
        []
      end
      articles.uniq(&:id).uniq(&:canonical_url)
    end
  end
end
