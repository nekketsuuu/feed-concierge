# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module FeedConcierge
  module Sources
    class FetchError < StandardError; end

    module Http
      USER_AGENT = "feed-concierge/0.1"
      ACCEPT = "text/html,application/xhtml+xml,application/xml,application/rss+xml,application/atom+xml," \
               "application/json;q=0.9,*/*;q=0.8"

      module_function

      # Final URL after following redirects, without fetching the body; used for tracking links.
      def resolve(url, hops: 5)
        uri = URI(url)
        hops.times do
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                         open_timeout: 15, read_timeout: 30) do |http|
            http.request_head(uri.request_uri, "User-Agent" => USER_AGENT, "Accept" => ACCEPT)
          end
          return uri.to_s unless response.is_a?(Net::HTTPRedirection) && response["location"]

          uri = URI.join(uri, response["location"])
        end
        uri.to_s
      end

      RETRYABLE_STATUSES = %w[429 500 502 503 504].freeze
      NETWORK_ERRORS = [SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError, IOError].freeze
      MAX_ATTEMPTS = 5

      # Retries transient failures with exponential backoff and jitter before giving up.
      def get(url, redirects_left: 3, user_agent: USER_AGENT)
        attempt = 0
        loop do
          response = request(url, user_agent: user_agent)
          if response.is_a?(Net::HTTPRedirection) && response["location"] && redirects_left.positive?
            return get(URI.join(url, response["location"]).to_s, redirects_left: redirects_left - 1, user_agent: user_agent)
          end
          return decode(response.body) if response.is_a?(Net::HTTPSuccess)

          attempt += 1
          unless RETRYABLE_STATUSES.include?(response.code) && attempt < MAX_ATTEMPTS
            raise FetchError, "#{url}: HTTP #{response.code}"
          end

          sleep(backoff(attempt, response["retry-after"]))
        rescue *NETWORK_ERRORS => e
          attempt += 1
          raise FetchError, "#{url}: #{e.class}: #{e.message[0, 120]}" if attempt >= MAX_ATTEMPTS

          sleep(backoff(attempt, nil))
        end
      end

      # Without a user agent, Net::HTTP announces itself as Ruby; some hosts refuse unknown agents.
      def request(url, user_agent: USER_AGENT)
        uri = URI(url)
        headers = { "Accept" => ACCEPT }
        headers["User-Agent"] = user_agent if user_agent
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, headers)
        end
      end

      def backoff(attempt, retry_after)
        seconds = retry_after.to_f
        seconds = [2**(attempt - 1), 30].min if seconds <= 0
        seconds + rand
      end

      def decode(body)
        body = body.to_s
        body.force_encoding("UTF-8").valid_encoding? ? body : body.encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end
  end
end
