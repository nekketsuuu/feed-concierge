require "net/http"
require "json"
require "uri"

module HnConcierge
  class JevClient
    ENDPOINT = URI("https://api.typesafe.ai/v1/systemone")
    RETRYABLE = %w[429 529 500 502 503].freeze

    class Error < StandardError; end

    def initialize(api_key: ENV.fetch("TYPESAFE_API_KEY"), model: "jev-latest", max_retries: 5)
      @api_key = api_key
      @model = model
      @max_retries = max_retries
    end

    def system_one(state:, questions:)
      payload = { state: state, model: @model, questions: questions }
      attempt = 0
      begin
        response = post(payload)
        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

        if RETRYABLE.include?(response.code) && attempt < @max_retries
          attempt += 1
          sleep(backoff(attempt, response["retry-after"]))
          raise RetryRequest
        end
        raise Error, "TypeSafe API #{response.code}: #{response.body[0, 500]}"
      rescue RetryRequest
        retry
      end
    end

    private

    class RetryRequest < StandardError; end

    def post(payload)
      Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        request = Net::HTTP::Post.new(ENDPOINT.request_uri,
                                      "Authorization" => "Bearer #{@api_key}",
                                      "Content-Type" => "application/json")
        request.body = JSON.generate(payload)
        http.request(request)
      end
    end

    def backoff(attempt, retry_after)
      seconds = retry_after.to_f
      seconds = [2**attempt, 30].min if seconds <= 0
      seconds + rand
    end
  end

  # Used for local development without an API key. Returns deterministic pseudo answers.
  class FakeJevClient
    def system_one(state:, questions:)
      seed = state.to_json.sum
      answers = questions.to_h do |id, question|
        r = ((seed * (id.to_s.sum + 1)) % 1000) / 1000.0
        answer =
          case question[:type]
          when "score"
            levels = question[:criteria].size
            { "type" => "score", "score" => (r * (levels - 1)).round(2), "confidence" => 0.6 }
          when "noul"
            { "type" => "noul", "noul" => r.round(3) }
          end
        [id.to_s, answer]
      end
      { "model" => "fake-jev", "answers" => answers, "usage" => { "input_tokens" => 0, "output_tokens" => 0 } }
    end
  end
end
