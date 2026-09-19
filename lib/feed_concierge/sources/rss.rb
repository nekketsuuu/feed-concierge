# frozen_string_literal: true

require "rss"
require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # Plain RSS/Atom feeds without aggregator metadata (no points or comment counts).
    # The feed's own content (content:encoded, else description) is kept as a summary.
    class Rss
      def initialize(name:, feeds:, summary_max_chars: 600, max_age_days: nil)
        @name = name
        @feeds = feeds
        @summary_max_chars = summary_max_chars
        @max_age_days = max_age_days
      end

      def articles
        items = @feeds.flat_map { |url| fetch(url) }.uniq(&:id)
        return items unless @max_age_days

        cutoff = Time.now - @max_age_days * 86_400
        items.select { |a| a.published_at >= cutoff }
      end

      private

      def fetch(url)
        body = Http.get(url)
        feed = RSS::Parser.parse(body, false) or raise FetchError, "#{url}: not a feed"
        feed.items.filter_map { |item| to_article(item) }
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
          summary: strip_html(body_of(item))[0, @summary_max_chars]
        )
      end

      def body_of(item)
        encoded = item.respond_to?(:content_encoded) ? item.content_encoded.to_s : ""
        encoded.empty? ? item.description.to_s : encoded
      end

      def strip_html(html)
        text = html.gsub(%r{<(style|script)\b.*?</\1>}mi, " ").gsub(/<[^>]+>/, " ")
        CGI.unescapeHTML(text).gsub(/\s+/, " ").strip
      end
    end
  end
end
