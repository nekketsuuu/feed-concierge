# frozen_string_literal: true

require "json"
require "uri"

module FeedConcierge
  module Sources
    # Uses the JSON endpoints (hottest.json, newest.json), which carry score, tags, and comment counts.
    class Lobsters
      def initialize(feeds: ["https://lobste.rs/hottest.json"])
        @feeds = feeds
      end

      def articles
        @feeds.flat_map { |url| fetch(url) }.uniq(&:id)
      end

      private

      def fetch(url)
        body = Http.get(url)
        JSON.parse(body).map { |story| to_article(story) }
      end

      def to_article(story)
        Article.new(
          id: "lobsters:#{story["short_id"]}",
          source: "lobsters",
          title: story["title"].to_s.strip,
          url: story["url"].to_s.empty? ? story["comments_url"] : story["url"],
          comments_url: story["comments_url"],
          author: story["submitter_user"],
          points: story["score"],
          comment_count: story["comment_count"],
          published_at: Time.parse(story["created_at"]),
          summary: story["description_plain"].to_s.strip.then { |s| s.empty? ? nil : s[0, 600] },
          tags: story["tags"]
        )
      end
    end
  end
end
