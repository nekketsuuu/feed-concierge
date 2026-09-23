# frozen_string_literal: true

require "cgi"
require "date"

module FeedConcierge
  module Sources
    # OpenAI's API changelog page: dated, typed entries without titles or links, so each entry
    # becomes an article titled with its first sentence and linked to the page.
    class OpenaiChangelog
      URL = "https://developers.openai.com/changelog"
      ENTRY = %r{data-variant="outline">(?<day>(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[ ]\d{1,2})<.*?
                 <span[ ]class="capitalize[^"]*">(?<kind>[^<]+)</span>(?<badges>.*?)
                 _MarkdownContent_[^>]*>(?<body>.*?)</div></div>}mx

      def initialize(name: "openai_changelog", max_age_days: 14, summary_max_chars: 1200)
        @name = name
        @max_age_days = max_age_days
        @summary_max_chars = summary_max_chars
      end

      def articles
        cutoff = Time.now - (@max_age_days * 86_400)
        html = Http.get(URL)
        year = Time.now.year
        previous_month = 13
        html.to_enum(:scan, ENTRY).map { Regexp.last_match }.filter_map do |m|
          date = Date.parse("#{m[:day]} #{year}")
          year -= 1 if date.month > previous_month
          previous_month = date.month
          published = Time.utc(year, date.month, date.day)
          next if published < cutoff

          text = plain(m[:body])
          next if text.empty?

          key = "#{published.strftime('%Y-%m-%d')}-#{text.sum.to_s(36)}"
          Article.new(id: "#{@name}:#{key}", source: @name,
                      title: "OpenAI API #{m[:kind].downcase}: #{headline(text)}", url: "#{URL}##{key}",
                      published_at: published, summary: text[0, @summary_max_chars],
                      tags: [m[:kind]] + m[:badges].scan(/data-variant="soft">([^<]+)</).flatten.map(&:strip))
        end
      end

      private

      # Inline tags (code, links) vanish without leaving spaces; block tags become spaces.
      def plain(html)
        inline = html.gsub(%r{</?(?:code|a|em|strong|b|i|span)\b[^>]*>}, "")
        CGI.unescapeHTML(inline.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      end

      def headline(text)
        sentence = text.split(/(?<=[.!?])\s+/).first.to_s
        sentence.length > 110 ? "#{sentence[0, 107].rstrip}…" : sentence
      end
    end
  end
end
