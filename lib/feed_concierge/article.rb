require "uri"

module FeedConcierge
  Article = Struct.new(:id, :source, :title, :url, :comments_url, :author, :points, :comment_count, :published_at,
                       keyword_init: true) do
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
end
