# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"

module FeedConcierge
  class Site
    TEMPLATE = File.join(ROOT, "templates", "index.html.erb")

    def initialize(output_dir, site:, tag_config:)
      @output_dir = output_dir
      @site = site
      @tag_config = tag_config
    end

    def build(ranked, generated_at:, judged_count:)
      FileUtils.mkdir_p(@output_dir)
      File.write(File.join(@output_dir, "index.html"), render(ranked, generated_at, judged_count))
      File.write(File.join(@output_dir, "data.json"), JSON.pretty_generate(ranked.map { |r| to_json_row(r) }))
    end

    private

    def render(ranked, generated_at, judged_count)
      title = @site["title"]
      repository_url = @site["repository_url"]
      ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding)
    end

    def to_json_row(item)
      {
        id: item.article.id, source: item.article.source, title: item.article.title, url: item.article.url,
        comments_url: item.article.comments_url,
        published_at: item.article.published_at.iso8601, points: item.article.points, comments: item.article.comment_count,
        score: item.score.round(4), relevance: item.relevance.round(4), freshness: item.freshness.round(4),
        exposure: item.exposure.round(4), age_hours: item.age_hours.round(1), tags: tags_for(item),
        components: item.components.map { |c| c.transform_values { |v| v.is_a?(Float) ? v.round(3) : v } },
        tag_probabilities: (item.entry.dig("judgment", "tags") || {}).sort_by { |_, p| -p }.first(6).to_h,
        judgment: item.entry["judgment"]
      }
    end

    def h(text) = ERB::Util.html_escape(text)

    def tags_for(item)
      Judge.tags_for(item.entry["judgment"], min_probability: @tag_config["min_probability"], max: @tag_config["max_per_article"])
    end

    def local(time) = time.getlocal(@site["timezone"])

    def date_label(time) = local(time).strftime("%m-%d")

    def datetime_label(time) = "#{local(time).strftime('%Y-%m-%d %H:%M')} #{@site['timezone_label']}"
  end
end
