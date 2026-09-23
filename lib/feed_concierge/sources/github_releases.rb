# frozen_string_literal: true

require "json"
require "uri"
require "net/http"

module FeedConcierge
  module Sources
    # Releases of one GitHub repository, one article per release. Release notes are bullet lists
    # whose version-only titles say nothing, so Jev picks the changes worth catching up on and
    # they become the title.
    class GithubReleases
      def initialize(name:, repo:, product:, client:, lookback_days: 14, min_probability: 0.6, max_picks: 3,
                     max_bullets: 120, known: ->(_id) { false })
        @name = name
        @repo = repo
        @product = product
        @client = client
        @lookback_days = lookback_days
        @min_probability = min_probability
        @max_picks = max_picks
        @max_bullets = max_bullets
        @known = known
      end

      def articles
        cutoff = Time.now - (@lookback_days * 86_400)
        JSON.parse(get("/repos/#{@repo}/releases?per_page=30"))
            .reject { |rel| rel["draft"] || rel["prerelease"] }
            .select { |rel| rel["published_at"] && Clock.parse(rel["published_at"]) >= cutoff }
            .reject { |rel| @known.call(id_of(rel)) }
            .map { |rel| to_article(rel) }
      end

      private

      def id_of(rel) = "#{@name}:#{rel['tag_name']}"

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
        version = rel["tag_name"].to_s.delete_prefix("v")
        bullets = bullets_of(rel["body"].to_s)
        picks = bullets.empty? ? [] : pick(bullets)
        title = "#{@product} #{version}: #{picks.empty? ? describe(bullets) : picks.map { |b| headline(b) }.join(' · ')}"
        rest = bullets.size - picks.size
        summary = (picks.map { |b| "- #{b}" } + (rest.positive? ? ["…and #{rest} more changes"] : [])).join("\n")
        Article.new(id: id_of(rel), source: @name, title: title, url: rel["html_url"],
                    published_at: Clock.parse(rel["published_at"]), summary: summary[0, 1500])
      end

      def bullets_of(body)
        body.lines.map(&:strip).select { |l| l.start_with?("- ", "* ") }.map { |l| l[2..].strip }.first(@max_bullets)
      end

      # One Noul per bullet, all in one request; the bullets above the threshold become the title.
      def pick(bullets)
        changes = bullets.each_with_index.to_h { |b, i| ["c#{i}", b] }
        questions = bullets.each_index.to_h do |i|
          ["catchup_c#{i}", {
            type: "noul",
            instructions: "Is `release.changes.c#{i}` a change the reader described in `reader_profile` should catch up on: " \
                          "something that changes how they use the tool, a new capability, or a changed default?",
            criteria: {
              "true" => "A new capability, a changed default or behaviour, a removal or deprecation, or a fix to something the reader likely hits every day.",
              "false" => "A fix for a rare crash or edge case, an internal or enterprise-only detail, a change only in an editor extension, or a cosmetic change."
            }
          }]
        end
        state = { reader_profile: FeedConcierge.reader_profile, release: { product: @product, changes: changes } }
        answers = @client.system_one(state: state, questions: questions).fetch("answers")
        bullets.each_index.map { |i| [answers.dig("catchup_c#{i}", "noul").to_f, i] }
               .select { |p, _| p >= @min_probability }
               .sort_by { |p, i| [-p, i] }
               .first(@max_picks)
               .sort_by(&:last)
               .map { |_, i| bullets[i] }
      end

      def headline(bullet)
        bullet.split(/[:;(,]| — | - /, 2).first.strip[0, 50]
      end

      def describe(bullets)
        return "no listed changes" if bullets.empty?

        noun = bullets.all? { |b| b.start_with?("Fixed") } ? "fix" : "change"
        "#{bullets.size} #{noun}#{'s' unless bullets.size == 1}"
      end
    end
  end
end
