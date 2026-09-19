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
        cutoff = (Time.now.utc - (@lookback_days * 86_400)).strftime("%Y-%m-%d")
        JSON.parse(Http.get(FEED)).fetch("vulnerabilities")
            .select { |v| v["dateAdded"] >= cutoff }
            .map { |v| to_article(v) }
            .sort_by { |a| -a.published_at.to_i }
      end

      private

      def to_article(vuln)
        Article.new(
          id: "#{@name}:#{vuln["cveID"]}",
          source: @name,
          title: "#{vuln["cveID"]}: #{vuln["vulnerabilityName"]}",
          url: "https://nvd.nist.gov/vuln/detail/#{vuln["cveID"]}",
          published_at: Time.parse("#{vuln["dateAdded"]}T00:00:00Z"),
          summary: "#{vuln["shortDescription"]} Known ransomware campaign use: #{vuln["knownRansomwareCampaignUse"]}.",
          tags: [vuln["vendorProject"], vuln["product"], *vuln["cwes"].to_a].compact
        )
      end
    end
  end
end
