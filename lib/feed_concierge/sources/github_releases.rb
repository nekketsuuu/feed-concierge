# frozen_string_literal: true

require "json"
require "uri"
require "net/http"

module FeedConcierge
  module Sources
    # Releases of one GitHub repository, one article per release. Projects that ship several
    # maintenance lines on the same day keep only the newest with newest_per_day.
    class GithubReleases
      include ReleaseNotes

      def initialize(name:, repo:, product:, client:, lookback_days: 14, min_probability: 0.6, max_picks: 3,
                     max_bullets: 120, sections: nil, newest_per_day: false, known: ->(_id) { false })
        @name = name
        @repo = repo
        @product = product
        @client = client
        @lookback_days = lookback_days
        @min_probability = min_probability
        @max_picks = max_picks
        @max_bullets = max_bullets
        @sections = sections
        @newest_per_day = newest_per_day
        @known = known
      end

      def articles
        cutoff = Time.now - (@lookback_days * 86_400)
        releases = JSON.parse(get("/repos/#{@repo}/releases?per_page=30"))
                       .reject { |rel| rel["draft"] || rel["prerelease"] }
                       .select { |rel| rel["published_at"] && Clock.parse(rel["published_at"]) >= cutoff }
        releases = newest_of_each_day(releases) if @newest_per_day
        releases.reject { |rel| @known.call(id_of(rel)) }.map { |rel| to_article(rel) }
      end

      private

      def id_of(rel) = "#{@name}:#{rel['tag_name']}"
      def version_of(rel) = rel["tag_name"].to_s.sub(/\A\D*/, "")

      def newest_of_each_day(releases)
        releases.group_by { |rel| rel["published_at"][0, 10] }.values
                .map { |same_day| same_day.max_by { |rel| version_of(rel).scan(/\d+/).map(&:to_i) } }
      end

      def get(path)
        uri = URI("https://api.github.com#{path}")
        headers = { "User-Agent" => "feed-concierge/0.1", "Accept" => "application/vnd.github+json" }
        headers["Authorization"] = "Bearer #{ENV['GITHUB_TOKEN']}" unless ENV["GITHUB_TOKEN"].to_s.empty?
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, headers)
        end
        raise FetchError, "#{uri}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end

      def to_article(rel)
        release_article(id: id_of(rel), version: version_of(rel), url: rel["html_url"],
                        published_at: Clock.parse(rel["published_at"]), bullets: bullets_of(rel["body"].to_s))
      end

      # With a sections allowlist, only bullets under those markdown headings count.
      def bullets_of(body)
        heading = nil
        body.lines.map(&:strip).filter_map do |line|
          heading = line.sub(/\A#+\s*/, "") and next if line.start_with?("#")
          next unless line.start_with?("- ", "* ")
          next if @sections && !@sections.include?(heading)

          line[2..].strip
        end.first(@max_bullets)
      end
    end
  end
end
