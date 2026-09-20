# frozen_string_literal: true

require "net/http"
require "uri"

module FeedConcierge
  module Sources
    class FetchError < StandardError; end

    module Http
      module_function

      # Final URL after following redirects, without fetching the body; used for tracking links.
      def resolve(url, hops: 5)
        uri = URI(url)
        hops.times do
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                         open_timeout: 15, read_timeout: 30) do |http|
            http.request_head(uri.request_uri, "User-Agent" => "feed-concierge/0.1")
          end
          return uri.to_s unless response.is_a?(Net::HTTPRedirection) && response["location"]

          uri = URI.join(uri, response["location"])
        end
        uri.to_s
      end

      def get(url, redirects_left: 3)
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                       open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, "User-Agent" => "feed-concierge/0.1")
        end
        if response.is_a?(Net::HTTPRedirection) && response["location"] && redirects_left.positive?
          return get(URI.join(uri, response["location"]).to_s, redirects_left: redirects_left - 1)
        end
        raise FetchError, "#{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        body.force_encoding("UTF-8").valid_encoding? ? body : body.encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end
  end
end
