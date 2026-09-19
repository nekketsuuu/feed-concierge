require "net/http"
require "uri"

module FeedConcierge
  module Sources
    class FetchError < StandardError; end

    module Http
      module_function

      def get(url)
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                   open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, "User-Agent" => "feed-concierge/0.1")
        end
        raise FetchError, "#{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end
    end
  end
end
