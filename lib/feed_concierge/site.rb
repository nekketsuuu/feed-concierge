require "erb"
require "fileutils"
require "json"

module FeedConcierge
  class Site
    TEMPLATE = File.join(ROOT, "templates", "index.html.erb")

    def initialize(output_dir, title:, source_labels: {})
      @output_dir = output_dir
      @title = title
      @source_labels = source_labels
    end

    def build(ranked, generated_at:, judged_count:)
      FileUtils.mkdir_p(@output_dir)
      File.write(File.join(@output_dir, "index.html"), render(ranked, generated_at, judged_count))
      File.write(File.join(@output_dir, "data.json"), JSON.pretty_generate(ranked.map { |r| to_json_row(r) }))
    end

    private

    def render(ranked, generated_at, judged_count)
      title = @title
      source_labels = @source_labels
      ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding)
    end

    def to_json_row(r)
      {
        id: r.article.id, source: r.article.source, title: r.article.title, url: r.article.url, comments_url: r.article.comments_url,
        published_at: r.article.published_at.iso8601, points: r.article.points, comments: r.article.comment_count,
        score: r.score.round(4), relevance: r.relevance.round(4), freshness: r.freshness.round(4),
        exposure: r.exposure.round(4), judgment: r.entry["judgment"]
      }
    end

    def h(text) = ERB::Util.html_escape(text)

    def age_label(hours)
      hours < 1 ? "#{(hours * 60).round}m" : hours < 48 ? "#{hours.round}h" : "#{(hours / 24).round}d"
    end

    def pct(value) = "#{(value.to_f * 100).round}%"
  end
end
