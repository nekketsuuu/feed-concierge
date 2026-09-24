# frozen_string_literal: true

require "json"
require "uri"

module FeedConcierge
  module Sources
    # Hacker News stories through the Algolia search API: every story submitted within the
    # lookback window that has reached min_points, independent of when the build runs.
    # Article ids are prefixed with "hn:" so other sources can never collide.
    class HackerNews
      ENDPOINT = "https://hn.algolia.com/api/v1/search_by_date"
      PAGE_SIZE = 1000

      def initialize(lookback_hours: 48, min_points: 30)
        @lookback_hours = lookback_hours
        @min_points = min_points
      end

      def articles
        since = Time.now.to_i - (@lookback_hours * 3600)
        page = 0
        hits = []
        loop do
          data = JSON.parse(Http.get(url(since, page)))
          hits.concat(data.fetch("hits"))
          page += 1
          break if page >= data.fetch("nbPages", 1).to_i
        end
        hits.map { |hit| to_article(hit) }.uniq(&:id)
      end

      private

      def url(since, page)
        query = URI.encode_www_form(tags: "story", numericFilters: "created_at_i>#{since},points>=#{@min_points}",
                                    hitsPerPage: PAGE_SIZE, page: page)
        "#{ENDPOINT}?#{query}"
      end

      def to_article(hit)
        comments_url = "https://news.ycombinator.com/item?id=#{hit['objectID']}"
        Article.new(
          id: "hn:#{hit['objectID']}",
          source: "hacker_news",
          title: hit["title"].to_s.strip,
          url: hit["url"].to_s.empty? ? comments_url : hit["url"],
          comments_url: comments_url,
          author: hit["author"],
          points: hit["points"].to_i,
          comment_count: hit["num_comments"].to_i,
          published_at: Clock.parse(hit["created_at"]),
          summary: hit["story_text"].to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip.then { |t| t.empty? ? nil : t[0, 1500] }
        )
      end
    end
  end
end
