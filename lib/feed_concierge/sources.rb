require_relative "sources/hacker_news"

module FeedConcierge
  module Sources
    REGISTRY = { "hacker_news" => HackerNews }.freeze

    # Builds sources from config/settings.yml entries like:
    #   - type: hacker_news
    #     feeds: [https://hnrss.org/frontpage]
    def self.build(configs)
      configs.map do |cfg|
        klass = REGISTRY.fetch(cfg.fetch("type")) { raise ArgumentError, "unknown source type: #{cfg["type"]}" }
        klass.new(**cfg.except("type").transform_keys(&:to_sym))
      end
    end

    def self.fetch_all(configs)
      build(configs).flat_map(&:articles).uniq(&:id)
    end
  end
end
