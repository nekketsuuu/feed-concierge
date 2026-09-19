# frozen_string_literal: true

require "rss"
require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # Plain RSS 2.0, RSS 1.0, or Atom feeds without aggregator metadata (no points or comment
    # counts). The feed's own content is kept as a summary.
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
        link = link_of(item)
        return if link.empty?

        Article.new(
          id: "#{@name}:#{id_of(item) || link}",
          source: @name,
          title: text_of(item.title).strip,
          url: link,
          author: author_of(item),
          published_at: published_at_of(item),
          summary: strip_html(body_of(item))[0, @summary_max_chars]
        )
      end

      def link_of(item)
        return item.link.to_s unless item.respond_to?(:links)

        link = item.links.find { |l| l.rel.nil? || l.rel == "alternate" } || item.links.first
        link&.href.to_s
      end

      def id_of(item)
        return item.guid&.content if item.respond_to?(:guid)

        item.id&.content if item.respond_to?(:id)
      end

      def author_of(item)
        creator = item.respond_to?(:dc_creator) ? item.dc_creator.to_s : ""
        return creator unless creator.empty?

        item.author.name.content if item.respond_to?(:author) && item.author.respond_to?(:name)
      end

      def published_at_of(item)
        %i[pubDate published updated date].each do |field|
          next unless item.respond_to?(field)

          value = item.public_send(field)
          value = value.content if value.respond_to?(:content)
          return Clock.parse(value) if value
        end
        Time.now
      end

      def body_of(item)
        candidates = []
        candidates << item.content_encoded if item.respond_to?(:content_encoded)
        candidates << item.description if item.respond_to?(:description)
        candidates << item.content if item.respond_to?(:content)
        candidates << item.summary if item.respond_to?(:summary)
        candidates.map { |c| text_of(c) }.find { |t| !t.empty? } || ""
      end

      def text_of(value)
        value = value.content if value.respond_to?(:content)
        value.to_s
      end

      def strip_html(html)
        text = html.gsub(%r{<(style|script)\b.*?</\1>}mi, " ").gsub(/<[^>]+>/, " ")
        CGI.unescapeHTML(text).gsub(/\s+/, " ").strip
      end
    end
  end
end
