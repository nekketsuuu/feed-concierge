require "rss"
require "uri"

module FeedConcierge
  module Sources
    # Reads hnrss.org feeds. Article ids are prefixed with "hn:" so other sources can never collide.
    class HackerNews
      def initialize(feeds:)
        @feeds = feeds
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
        item_id = item.guid&.content.to_s[/id=(\d+)/, 1]
        return unless item_id

        Article.new(
          id: "hn:#{item_id}",
          source: "hacker_news",
          title: item.title.to_s.strip,
          url: item.link.to_s,
          comments_url: item.comments.to_s,
          author: item.dc_creator.to_s,
          points: item.description.to_s[/Points:\s*(\d+)/, 1].to_i,
          comment_count: item.description.to_s[/# Comments:\s*(\d+)/, 1].to_i,
          published_at: item.pubDate || Time.now
        )
      end
    end
  end
end
