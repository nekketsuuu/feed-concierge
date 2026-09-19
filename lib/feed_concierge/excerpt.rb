# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"

module FeedConcierge
  module Excerpt
    SKIP_HOSTS = %w[news.ycombinator.com twitter.com x.com youtube.com github.com].freeze

    module_function

    def fetch(url, max_chars:, timeout:)
      uri = URI(url)
      return nil unless uri.is_a?(URI::HTTP)
      return nil if SKIP_HOSTS.include?(uri.host.to_s.delete_prefix("www."))

      response = get_with_redirects(uri, timeout)
      return nil unless response.is_a?(Net::HTTPSuccess)
      return nil unless response["content-type"].to_s.include?("html")

      text = html_to_text(response.body.to_s.force_encoding("UTF-8").scrub)
      text.empty? ? nil : text[0, max_chars]
    rescue StandardError, Timeout::Error
      nil
    end

    def get_with_redirects(uri, timeout, limit = 3)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: timeout, read_timeout: timeout) do |http|
        http.request_get(uri.request_uri, "User-Agent" => "feed-concierge/0.1")
      end
      if response.is_a?(Net::HTTPRedirection) && limit.positive? && response["location"]
        get_with_redirects(URI.join(uri, response["location"]), timeout, limit - 1)
      else
        response
      end
    end

    def html_to_text(html)
      body = html[/<body.*?>(.*)<\/body>/mi, 1] || html
      body = body.gsub(/<(script|style|nav|header|footer|noscript|svg)\b.*?<\/\1>/mi, " ")
      body = body.gsub(/<!--.*?-->/m, " ")
      body = body.gsub(/<[^>]+>/, " ")
      CGI.unescapeHTML(body).gsub(/\s+/, " ").strip
    end
  end
end
