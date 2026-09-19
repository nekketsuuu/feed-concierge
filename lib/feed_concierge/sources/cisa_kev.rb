# frozen_string_literal: true

require "json"
require "time"

module FeedConcierge
  module Sources
    # CVEs recently added to CISA's Known Exploited Vulnerabilities catalog.
    class CisaKev
      FEED = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"

      def initialize(name: "cisa_kev", lookback_days: 7)
        @name = name
        @lookback_days = lookback_days
      end

      def articles
        cutoff = (Time.now.utc - @lookback_days * 86_400).strftime("%Y-%m-%d")
        JSON.parse(Http.get(FEED)).fetch("vulnerabilities")
            .select { |v| v["dateAdded"] >= cutoff }
            .map { |v| to_article(v) }
            .sort_by { |a| -a.published_at.to_i }
      end

      private

      def to_article(v)
        Article.new(
          id: "#{@name}:#{v["cveID"]}",
          source: @name,
          title: "#{v["cveID"]}: #{v["vulnerabilityName"]}",
          url: "https://nvd.nist.gov/vuln/detail/#{v["cveID"]}",
          published_at: Time.parse("#{v["dateAdded"]}T00:00:00Z"),
          summary: "#{v["shortDescription"]} Known ransomware campaign use: #{v["knownRansomwareCampaignUse"]}.",
          tags: [v["vendorProject"], v["product"], *v["cwes"].to_a].compact
        )
      end
    end
  end
end
