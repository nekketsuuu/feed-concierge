# frozen_string_literal: true

require "json"
require "uri"
require "net/http"

module FeedConcierge
  module Sources
    # Security advisories from GitHub's global advisory database for the configured package
    # ecosystems (for example rubygems). GITHUB_TOKEN is sent when present.
    class GithubAdvisories
      PAGE_SIZE = 100

      def initialize(name: "github_advisories", ecosystems: ["rubygems"], lookback_days: 14, description_max_chars: 1500)
        @name = name
        @ecosystems = ecosystems
        @lookback_days = lookback_days
        @description_max_chars = description_max_chars
      end

      def articles
        cutoff = Time.now - (@lookback_days * 86_400)
        @ecosystems.flat_map { |ecosystem| JSON.parse(get(ecosystem)) }
                   .select { |adv| Clock.parse(adv["published_at"]) >= cutoff }
                   .map { |adv| to_article(adv) }
                   .uniq(&:id)
                   .sort_by { |a| -a.published_at.to_i }
      end

      private

      def get(ecosystem)
        query = URI.encode_www_form(ecosystem: ecosystem, per_page: PAGE_SIZE, sort: "published", direction: "desc")
        uri = URI("https://api.github.com/advisories?#{query}")
        headers = { "User-Agent" => "feed-concierge/0.1", "Accept" => "application/vnd.github+json" }
        headers["Authorization"] = "Bearer #{ENV['GITHUB_TOKEN']}" unless ENV["GITHUB_TOKEN"].to_s.empty?
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.request_get(uri.request_uri, headers)
        end
        raise FetchError, "#{uri}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end

      def summary_of(adv, packages)
        text = "Affected packages: #{packages.join(', ')}. Severity: #{adv['severity']}. #{adv['description'].to_s.strip}"
        text[0, @description_max_chars]
      end

      def to_article(adv)
        packages = adv["vulnerabilities"].to_a.map { |v| "#{v.dig('package', 'ecosystem')}/#{v.dig('package', 'name')}" }.uniq
        Article.new(
          id: "#{@name}:#{adv['ghsa_id']}",
          source: @name,
          title: "#{adv['cve_id'] || adv['ghsa_id']}: #{adv['summary'].to_s.strip}",
          url: adv["html_url"],
          published_at: Clock.parse(adv["published_at"]),
          summary: summary_of(adv, packages),
          tags: [*packages, adv["severity"], *adv["cwes"].to_a.map { |c| c["cwe_id"] }].compact
        )
      end
    end
  end
end
