# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"

module FeedConcierge
  class Site
    TEMPLATE = File.join(ROOT, "templates", "index.html.erb")
    TUNE_TEMPLATE = File.join(ROOT, "templates", "tune.html.erb")

    def initialize(output_dir, site:, tag_config:, ranking_config:)
      @output_dir = output_dir
      @site = site
      @tag_config = tag_config
      @ranking_config = ranking_config
    end

    def build(ranked, candidates:, generated_at:, judged_count:)
      FileUtils.mkdir_p(@output_dir)
      File.write(File.join(@output_dir, "index.html"), render(ranked, generated_at, judged_count))
      File.write(File.join(@output_dir, "tune.html"), render_tune(ranked, candidates, generated_at))
      File.write(File.join(@output_dir, "data.json"), JSON.pretty_generate(ranked.map { |r| to_json_row(r) }))
    end

    private

    def render(ranked, generated_at, judged_count)
      title = @site["title"]
      repository_url = @site["repository_url"]
      ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding)
    end

    def render_tune(ranked, candidates, generated_at)
      title = @site["title"]
      repository_url = @site["repository_url"]
      tune_data = tune_json(ranked, candidates)
      ERB.new(File.read(TUNE_TEMPLATE), trim_mode: "-").result(binding)
    end

    def to_json_row(item)
      {
        id: item.article.id, source: item.article.source, title: item.article.title, url: item.article.url,
        comments_url: item.article.comments_url,
        published_at: item.article.published_at.iso8601, points: item.article.points, comments: item.article.comment_count,
        score: item.score.round(4), relevance: item.relevance.round(4), freshness: item.freshness.round(4),
        age_hours: item.age_hours.round(1), tags: tags_for(item),
        components: item.components.map { |c| c.transform_values { |v| v.is_a?(Float) ? v.round(3) : v } },
        tag_probabilities: (item.entry.dig("judgment", "tags") || {}).sort_by { |_, p| -p }.first(6).to_h,
        judgment: item.entry["judgment"]
      }
    end

    # Everything the tune page needs to re-rank in the browser: the ranking config and, for
    # every candidate, the raw answers behind its score. Embedded in the page because browsers
    # refuse fetch() on file:// pages.
    def tune_json(ranked, candidates)
      rank = ranked.each_with_index.to_h { |item, i| [item.article.id, i + 1] }
      f = @ranking_config["freshness"]
      config = { weights: @ranking_config["weights"], choice_weights: @ranking_config["choice_weights"] || {},
                 clicked_penalty: @site["clicked_penalty"],
                 min_score: @ranking_config["min_score"],
                 top_n: @ranking_config["top_n"],
                 max_per_source: @ranking_config["max_per_source"] || {},
                 freshness: { half_life_days: f["half_life_hours"] / 24.0,
                              bonus_days: f["evergreen_half_life_bonus_hours"] / 24.0,
                              floor: f["floor"], steepness: f["steepness"] } }
      rows = candidates.map do |item|
        judgment = item.entry["judgment"]
        { id: item.article.id, title: item.article.title, url: item.article.url, domain: item.article.domain,
          date: date_label(item.article.published_at), source: item.article.source, question_set: judgment["question_set"],
          dedup_key: item.article.dedup_key, baseline_rank: rank[item.article.id],
          age_hours: item.age_hours, evergreen: judgment["evergreen"].to_f,
          components: item.components.map { |c| { id: c[:id], value: c[:value] } },
          choices: judgment.select { |k, _| k.end_with?("_probabilities") } }
      end
      JSON.generate({ config: config, rows: rows }).gsub("</", "<\/")
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
