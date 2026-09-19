require "net/http"
require "rss"
require "uri"

module HnConcierge
  Article = Struct.new(:id, :title, :url, :comments_url, :author, :points, :comment_count, :published_at, keyword_init: true) do
    def domain
      URI(url).host&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    def to_h
      super.merge(published_at: published_at.iso8601)
    end

    def self.from_h(h)
      new(**h.transform_keys(&:to_sym).merge(published_at: Time.parse(h["published_at"])))
    end
  end

  module Feed
    module_function

    def fetch_all(urls)
      urls.flat_map { |url| fetch(url) }.uniq(&:id)
    end

    def fetch(url)
      body = Net::HTTP.get(URI(url))
      RSS::Parser.parse(body, false).items.filter_map { |item| to_article(item) }
    end

    def to_article(item)
      id = item.guid&.content.to_s[/id=(\d+)/, 1]
      return unless id

      Article.new(
        id: id,
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
