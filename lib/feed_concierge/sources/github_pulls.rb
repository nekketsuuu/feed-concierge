# frozen_string_literal: true

require "json"
require "uri"
require "net/http"

module FeedConcierge
  module Sources
    # Pull requests merged recently in one GitHub repository. Uses the REST list endpoint
    # sorted by update time, so a single unauthenticated request covers a few days;
    # GITHUB_TOKEN is sent when present (GitHub Actions provides one).
    class GithubPulls
      PAGE_SIZE = 100
      MAX_PAGES = 3

      def initialize(name:, repo:, lookback_days: 3, base_branch: "main", body_max_chars: 1500,
                     exclude_authors: ["dependabot[bot]"])
        @name = name
        @repo = repo
        @lookback_days = lookback_days
        @base_branch = base_branch
        @body_max_chars = body_max_chars
        @exclude_authors = exclude_authors
      end

      def articles
        cutoff = Time.now - @lookback_days * 86_400
        merged = []
        (1..MAX_PAGES).each do |page|
          pulls = JSON.parse(get(page))
          merged.concat(pulls.select { |pr| merged_recently?(pr, cutoff) })
          break if pulls.size < PAGE_SIZE || Clock.parse(pulls.last["updated_at"]) < cutoff
        end
        merged.map { |pr| to_article(pr) }.sort_by { |a| -a.published_at.to_i }
      end

      private

      def merged_recently?(pr, cutoff)
        return false unless pr["merged_at"] && Clock.parse(pr["merged_at"]) >= cutoff
        return false if @base_branch && pr.dig("base", "ref") != @base_branch

        !@exclude_authors.include?(pr.dig("user", "login"))
      end

      def get(page)
        uri = URI("https://api.github.com/repos/#{@repo}/pulls?" \
                  "#{URI.encode_www_form(state: "closed", sort: "updated", direction: "desc", per_page: PAGE_SIZE, page: page)}")
        headers = { "User-Agent" => "feed-concierge/0.1", "Accept" => "application/vnd.github+json" }
        headers["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}" unless ENV["GITHUB_TOKEN"].to_s.empty?
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, headers)
        end
        raise FetchError, "#{uri}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end

      def to_article(pr)
        Article.new(
          id: "#{@name}:#{pr["number"]}",
          source: @name,
          title: "#{@repo}##{pr["number"]} #{pr["title"].to_s.strip}",
          url: pr["html_url"],
          author: pr.dig("user", "login"),
          published_at: Clock.parse(pr["merged_at"]),
          summary: clean_body(pr["body"].to_s)[0, @body_max_chars],
          tags: pr["labels"].to_a.map { |l| l["name"] }
        )
      end

      def clean_body(body)
        body.gsub(/<!--.*?-->/m, " ").gsub("\r\n", "\n").gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end
