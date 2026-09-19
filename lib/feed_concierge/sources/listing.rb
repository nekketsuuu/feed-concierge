# frozen_string_literal: true

require "uri"
require "cgi"

module FeedConcierge
  module Sources
    # An HTML index page for sites without a feed. Configured with regexes: item_regex must
    # capture `href` and usually `block` (the item's markup); title, date, and summary are then
    # taken from named captures or looked up inside the block. Pages that print one date per
    # group of items (a month heading) use date_before to pick the nearest date above the item;
    # items without any date are dated when first seen unless require_date drops them (which
    # also filters out navigation links that match item_regex).
    class Listing
      DATE = /(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.? \d{1,2}, \d{4}|\d{4}-\d{2}-\d{2}/
      HEADING = %r{<h[1-4][^>]*>(?<title>.*?)</h[1-4]>}m

      def initialize(name:, url:, item_regex:, title_regex: nil, date_regex: nil, summary_regex: nil,
                     date_before: false, require_date: false, max_age_days: nil, summary_max_chars: 600)
        @name = name
        @url = url
        @item_regex = Regexp.new(item_regex, Regexp::MULTILINE)
        @title_regex = title_regex && Regexp.new(title_regex, Regexp::MULTILINE)
        @date_regex = date_regex && Regexp.new(date_regex, Regexp::MULTILINE)
        @summary_regex = summary_regex && Regexp.new(summary_regex, Regexp::MULTILINE)
        @date_before = date_before
        @require_date = require_date
        @max_age_days = max_age_days
        @summary_max_chars = summary_max_chars
      end

      def articles
        html = Http.get(@url)
        cutoff = @max_age_days && (Time.now - (@max_age_days * 86_400))
        html.to_enum(:scan, @item_regex).map { Regexp.last_match }
            .filter_map { |m| to_article(html, m) }
            .uniq(&:id)
            .select { |a| cutoff.nil? || a.published_at.nil? || a.published_at >= cutoff }
      end

      private

      def to_article(html, match)
        block = named(match, :block) || match[0]
        url = URI.join(@url, named(match, :href)).to_s
        title = text(named(match,
                           :title) || find(block, @title_regex, :title) || find(block, HEADING, :title) || without_meta(block))
        date = named(match, :date) || find(block, @date_regex, :date) || block[DATE]
        date ||= last_date_before(html, match.begin(0)) if @date_before
        return if title.empty? || (@require_date && date.nil?)

        Article.new(id: "#{@name}:#{url}", source: @name, title: title, url: url,
                    published_at: date && Clock.parse(text(date)),
                    summary: text(named(match, :summary) || find(block, @summary_regex, :summary))[0, @summary_max_chars])
      end

      def named(match, name) = match.names.include?(name.to_s) ? match[name] : nil

      def find(block, regex, name)
        return nil unless regex && (m = block.match(regex))

        m.names.include?(name.to_s) ? m[name] : m[0]
      end

      def last_date_before(html, position)
        regex = @date_regex || DATE
        html[0...position].to_enum(:scan, regex).map {
          Regexp.last_match
        }.last&.then { |m| m.names.include?("date") ? m[:date] : m[0] }
      end

      # Card text minus the element that wraps its date and category label.
      def without_meta(block)
        block.sub(%r{<(div|span|p)[^>]*>(?:(?!</>).)*<time.*?</>}m, " ")
      end

      def text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end
    end
  end
end
