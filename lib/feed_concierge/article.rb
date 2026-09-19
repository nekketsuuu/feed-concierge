require "uri"

module FeedConcierge
  Article = Struct.new(:id, :source, :title, :url, :comments_url, :author, :points, :comment_count,
                       :published_at, :summary, :tags, keyword_init: true) do
    def domain
      URI(url).host&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    # Used to recognise the same link submitted to several aggregators.
    def canonical_url
      uri = URI(url)
      query = URI.decode_www_form(uri.query.to_s).reject { |k, _| k.start_with?("utm_") || k == "ref" }
      "#{uri.host.to_s.delete_prefix("www.")}#{uri.path.to_s.chomp("/")}#{query.empty? ? "" : "?#{URI.encode_www_form(query)}"}".downcase
    rescue URI::InvalidURIError, ArgumentError
      url
    end

    def to_h
      super.merge(published_at: published_at.iso8601)
    end

    def self.from_h(h)
      new(**h.transform_keys(&:to_sym).merge(published_at: Time.parse(h["published_at"])))
    end
  end
end
