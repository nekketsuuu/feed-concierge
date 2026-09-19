# frozen_string_literal: true

require "json"
require "fileutils"

module FeedConcierge
  # Persists per-article judgments so each article is sent to Jev only once,
  # and remembers when an article first appeared on the page.
  class Store
    attr_reader :path

    def initialize(path)
      @path = path
      @entries = File.exist?(path) ? JSON.parse(File.read(path)).fetch("articles", {}) : {}
    end

    def [](id) = @entries[id]

    # An article is re-judged when its source switches to a different question set or the questions change.
    def judged?(id, question_set: "default")
      judgment = @entries.dig(id, "judgment") or return false
      (judgment["question_set"] || "default") == question_set && judgment["version"] == Judge::VERSION &&
        Judge.complete?(judgment, question_set)
    end

    def judged_url?(canonical_url)
      @entries.each_value.any? { |e| e["judgment"] && Article.from_h(e["article"]).canonical_url == canonical_url }
    end

    def remember(article, judgment:, excerpt_used:)
      entry = (@entries[article.id] ||= { "first_seen_at" => Time.now.utc.iso8601 })
      entry["article"] = article.to_h.transform_keys(&:to_s)
      entry["judgment"] = judgment
      entry["judged_at"] = Time.now.utc.iso8601
      entry["excerpt_used"] = excerpt_used
    end

    def refresh_stats(article)
      entry = @entries[article.id] or return
      entry["article"].merge!("points" => article.points, "comment_count" => article.comment_count,
                              "published_at" => article.published_at.iso8601)
    end

    def mark_shown(ids, now: Time.now)
      ids.each do |id|
        entry = @entries[id] or next
        entry["first_shown_at"] ||= now.utc.iso8601
        entry["shown_count"] = entry["shown_count"].to_i + 1
      end
    end

    def each_article
      @entries.each_value.map { |e| [Article.from_h(e["article"]), e] }
    end

    # Entries older than the retention window are forgotten entirely, so an article that is
    # still in a feed after that is judged again and starts with a clean exposure.
    def prune!(retention_days:, now: Time.now)
      cutoff = now - (retention_days * 86_400)
      @entries.delete_if { |_, e| Time.parse(e["first_seen_at"]) < cutoff }
    end

    def save
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate({ "updated_at" => Time.now.utc.iso8601, "articles" => @entries }))
    end
  end
end
