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

          text = CGI.unescapeHTML(m[:body].gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
          next if text.empty?

          Article.new(id: "#{@name}:#{published.strftime('%Y-%m-%d')}:#{text.hash.abs.to_s(36)}", source: @name,
                      title: "OpenAI API #{m[:kind].downcase}: #{headline(text)}", url: URL,
                      published_at: published, summary: text[0, @summary_max_chars],
                      tags: [m[:kind]] + m[:badges].scan(/data-variant="soft">([^<]+)</).flatten.map(&:strip))
        end
      end

      private

      def headline(text)
        sentence = text.split(/(?<=[.!?])\s+/).first.to_s
        sentence.length > 110 ? "#{sentence[0, 107].rstrip}…" : sentence
      end
    end
  end
end
