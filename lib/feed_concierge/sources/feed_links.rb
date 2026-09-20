# frozen_string_literal: true

require "rss"
require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # Turns the outbound links of recent feed entries (a weekly link roundup, say) into articles
    # dated with the entry. Titles come from the linked page when the anchor text is too short.
    class FeedLinks
      DEFAULT_EXCLUDES = %w[youtube.com youtu.be twitter.com x.com spotify.com amazon.com wikipedia.org
                            goodreads.com imdb.com news.ycombinator.com substackcdn.com].freeze
      MEDIA = /\.(png|jpe?g|gif|webp|svg|mp4|mp3|pdf)(\?|\z)/i

      def initialize(name:, feeds:, max_age_days: 14, max_links_per_entry: 40, min_anchor_chars: 20,
                     exclude_domains: [])
        @name = name
        @feeds = feeds
        @max_age_days = max_age_days
        @max_links_per_entry = max_links_per_entry
        @min_anchor_chars = min_anchor_chars
        @exclude_domains = DEFAULT_EXCLUDES + exclude_domains + @feeds.map { |f| URI(f).host.to_s.delete_prefix("www.") }
      end

      def articles
        cutoff = Time.now - (@max_age_days * 86_400)
        @feeds.flat_map do |url|
          feed = RSS::Parser.parse(Http.get(url), false) or raise FetchError, "#{url}: not a feed"
          feed.items.select { |item| item.pubDate && item.pubDate >= cutoff }.flat_map { |item| links_of(item) }
        end.uniq(&:id)
      end

      private

      def links_of(item)
        encoded = item.respond_to?(:content_encoded) ? item.content_encoded.to_s : ""
        body = encoded.empty? ? item.description.to_s : encoded
        body.scan(%r{<a [^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>}m)
            .map { |href, anchor| [CGI.unescapeHTML(href), text(anchor)] }
            .reject { |href, _| excluded?(href) || href.match?(MEDIA) }
            .uniq(&:first)
            .first(@max_links_per_entry)
            .filter_map { |href, anchor| to_article(href, anchor, item) }
      end

      def excluded?(href)
        host = URI(href).host.to_s.delete_prefix("www.")
        @exclude_domains.any? { |d| host == d || host.end_with?(".#{d}") }
      rescue URI::InvalidURIError
        true
      end

      def to_article(href, anchor, item)
        title = anchor.size >= @min_anchor_chars ? anchor : (page_title(href) || anchor)
        return if title.empty?

        Article.new(id: "#{@name}:#{href}", source: @name, title: title, url: href,
                    published_at: Clock.parse(item.pubDate), summary: "Linked from \"#{item.title}\" as: #{anchor}")
      end

      def page_title(href)
        html = Http.get(href)
        raw = html[/<meta[^>]+property="og:title"[^>]+content="([^"]+)"/i, 1] || html[%r{<title[^>]*>(.*?)</title>}mi, 1]
        raw && text(raw)
      rescue FetchError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        nil
      end

      def text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end
    end
  end
end
