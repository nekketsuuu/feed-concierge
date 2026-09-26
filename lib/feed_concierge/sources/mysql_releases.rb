# frozen_string_literal: true

require "uri"

module FeedConcierge
  module Sources
    # MySQL releases from the release notes index of each configured series (8.0, 8.4, ...).
    # dev.mysql.com refuses user agents it does not know, so these requests go out as plain Ruby.
    class MysqlReleases
      include ReleaseNotes

      INDEX = "https://dev.mysql.com/doc/relnotes/mysql/%s/en/"
      RELEASE = /<a[^>]+href="(?<href>news-[\d-]+\.html)"[^>]*>\s*
                Changes\ in\ MySQL\ (?<version>[\d.]+)\ \((?<date>\d{4}-\d{2}-\d{2})/x

      def initialize(name:, client:, series:, product: "MySQL", lookback_days: 14, min_probability: 0.6, max_picks: 3,
                     max_bullets: 120, known: ->(_id) { false })
        @name = name
        @client = client
        @series = series
        @product = product
        @lookback_days = lookback_days
        @min_probability = min_probability
        @max_picks = max_picks
        @max_bullets = max_bullets
        @known = known
      end

      def articles
        cutoff = Time.now - (@lookback_days * 86_400)
        @series.flat_map do |series|
          index = format(INDEX, series)
          Http.get(index, user_agent: nil).to_enum(:scan, RELEASE).map { Regexp.last_match }
              .uniq { |m| m[:version] }
              .select { |m| Clock.parse(m[:date]) >= cutoff }
              .reject { |m| @known.call("#{@name}:#{m[:version]}") }
              .map { |m| to_article(m, index) }
        end
      end

      private

      def to_article(match, index)
        url = URI.join(index, match[:href]).to_s
        release_article(id: "#{@name}:#{match[:version]}", version: match[:version], url: url,
                        published_at: Clock.parse(match[:date]), bullets: bullets_of(Http.get(url, user_agent: nil)))
      end

      # The page opens with a table of contents whose items are links; the changes follow. A
      # release with nothing listed (a docker-image-only patch) carries its note instead.
      def bullets_of(html)
        bullets = html.scan(%r{<li class="listitem">\s*<p>(.*?)</p>}m).flatten.reject { |p| p.lstrip.start_with?("<a") }
        bullets = html.scan(%r{<p>(.*?)</p>}m).flatten if bullets.empty?
        bullets.map { |p| text(p) }.first(@max_bullets)
      end
    end
  end
end
