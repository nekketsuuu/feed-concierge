# frozen_string_literal: true

require "rss"
require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # JPCERT/CC Weekly Report entries. The site feed lists one item per entry, each linking to an
    # anchor on the weekly page; the page is fetched once per week and split by those anchors so
    # every entry gets its own summary.
    class JpcertWeekly
      FEED = "https://www.jpcert.or.jp/rss/jpcert.rdf"

      def initialize(name: "jpcert_weekly", max_age_days: 14, summary_max_chars: 1200)
        @name = name
        @max_age_days = max_age_days
        @summary_max_chars = summary_max_chars
      end

      def articles
        feed = RSS::Parser.parse(Http.get(FEED), false) or raise FetchError, "#{FEED}: not a feed"
        cutoff = Time.now - (@max_age_days * 86_400)
        items = feed.items.select { |i|
          i.link.to_s.include?("/wr/") && i.link.to_s.include?("#") && (i.date || Time.now) >= cutoff
        }
        pages = items.map { |i| i.link.to_s.split("#").first }.uniq.to_h { |url| [url, sections(Http.get(url))] }
        items.map do |item|
          page, anchor = item.link.to_s.split("#", 2)
          Article.new(
            id: "#{@name}:#{item.link}",
            source: @name,
            title: item.title.to_s.strip,
            url: item.link.to_s,
            published_at: item.date || Time.now,
            summary: (pages[page][anchor] || item.description.to_s)[0, @summary_max_chars]
          )
        end
      end

      private

      # Entry bodies start at <a name="N"> and run until the next anchor or the closing <h2>.
      def sections(html)
        html.split(/(?=<a name="\d+">)/).each_with_object({}) do |chunk, out|
          anchor = chunk[/\A<a name="(\d+)">/, 1] or next
          body = chunk.split(/<h2>/).first
          out[anchor] = CGI.unescapeHTML(body.gsub(/<[^>]+>/, " ")).gsub(/[ \t　]+/, " ").gsub(/\s*\n\s*/, "\n").strip
        end
      end
    end
  end
end
