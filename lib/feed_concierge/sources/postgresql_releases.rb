# frozen_string_literal: true

require "rss"

module FeedConcierge
  module Sources
    # PostgreSQL minor releases from versions.rss, one article per release day: the newest of
    # the versions released together, with its release notes page read for the changes.
    class PostgresqlReleases
      include ReleaseNotes

      FEED = "https://www.postgresql.org/versions.rss"

      def initialize(name:, client:, product: "PostgreSQL", lookback_days: 14, min_probability: 0.6, max_picks: 3,
                     max_bullets: 120, known: ->(_id) { false })
        @name = name
        @client = client
        @product = product
        @lookback_days = lookback_days
        @min_probability = min_probability
        @max_picks = max_picks
        @max_bullets = max_bullets
        @known = known
      end

      def articles
        cutoff = Time.now - (@lookback_days * 86_400)
        feed = RSS::Parser.parse(Http.get(FEED), false) or raise FetchError, "#{FEED}: not a feed"
        feed.items.select { |item| item.pubDate && item.pubDate >= cutoff }
            .group_by { |item| item.pubDate.strftime("%F") }.values
            .filter_map do |same_day|
              newest, *others = same_day.sort_by { |item| version_of(item).split(".").map(&:to_i) }.reverse
              next if @known.call(id_of(newest))

              to_article(newest, others)
            end
      end

      private

      def version_of(item) = item.title.to_s.strip
      def id_of(item) = "#{@name}:#{version_of(item)}"

      def to_article(item, others)
        note = others.empty? ? nil : "Released together with #{others.map { |o| version_of(o) }.join(', ')}."
        release_article(id: id_of(item), version: version_of(item), url: item.link, published_at: Clock.parse(item.pubDate),
                        bullets: bullets_of(Http.get(item.link)), note: note)
      end

      def bullets_of(html)
        section = html[/id="RELEASE-[\w-]+-CHANGES".*/m] || html
        section.scan(%r{<li class="listitem">\s*<p>(.*?)</p>}m).flatten.map { |p| text(p) }.first(@max_bullets)
      end
    end
  end
end
