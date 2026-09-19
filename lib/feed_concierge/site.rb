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

    def to_json_row(r)
      {
        id: r.article.id, source: r.article.source, title: r.article.title, url: r.article.url,
        comments_url: r.article.comments_url,
        published_at: r.article.published_at.iso8601, points: r.article.points, comments: r.article.comment_count,
        score: r.score.round(4), relevance: r.relevance.round(4), freshness: r.freshness.round(4),
        exposure: r.exposure.round(4), tags: tags_for(r), judgment: r.entry["judgment"]
      }
    end

    def h(text) = ERB::Util.html_escape(text)

    def tags_for(r)
      Judge.tags_for(r.entry["judgment"], min_probability: @tag_config["min_probability"], max: @tag_config["max_per_article"])
    end

    def local(time) = time.getlocal(@site["timezone"])

    def date_label(time) = local(time).strftime("%m-%d")

    def datetime_label(time) = "#{local(time).strftime('%Y-%m-%d %H:%M')} #{@site['timezone_label']}"
  end
end
