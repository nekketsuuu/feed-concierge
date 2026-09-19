require "rss"
require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # Plain RSS/Atom feeds without aggregator metadata (no points or comment counts).
    # The feed's own description is kept as a summary for the model.
    class Rss
      def initialize(name:, feeds:, summary_max_chars: 600)
        @name = name
        @feeds = feeds
        @summary_max_chars = summary_max_chars
      end

      def articles
        @feeds.flat_map { |url| fetch(url) }.uniq(&:id)
      end

      private

      def fetch(url)
        body = Http.get(url)
        RSS::Parser.parse(body, false).items.filter_map { |item| to_article(item) }
      end

      def to_article(item)
        link = item.link.to_s
        return if link.empty?

        Article.new(
          id: "#{@name}:#{item.respond_to?(:guid) && item.guid ? item.guid.content : link}",
          source: @name,
          title: item.title.to_s.strip,
          url: link,
          author: item.respond_to?(:dc_creator) ? item.dc_creator.to_s : nil,
          published_at: (item.respond_to?(:pubDate) && item.pubDate) || (item.respond_to?(:date) && item.date) || Time.now,
          summary: strip_html(item.description.to_s)[0, @summary_max_chars]
        )
      end

      def strip_html(html)
        CGI.unescapeHTML(html.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end
    end
  end
end
