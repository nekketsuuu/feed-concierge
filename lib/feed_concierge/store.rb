require "json"
require "fileutils"

module FeedConcierge
  # Persists per-article judgments so each article is sent to Jev only once,
  # and remembers how often an article has already been shown on the page.
  class Store
    RETENTION_DAYS = 14

    attr_reader :path

    def initialize(path)
      @path = path
      @entries = File.exist?(path) ? JSON.parse(File.read(path)).fetch("articles", {}) : {}
    end

    def [](id) = @entries[id]

    # An article is re-judged when its source switches to a different question set or the questions change.
    def judged?(id, question_set: "default")
      judgment = @entries.dig(id, "judgment") or return false
      (judgment["question_set"] || "default") == question_set && judgment["version"] == Judge::VERSION
    end

def judged_url?(canonical_url)
  @entries.each_value.any? { |e| e["judgment"] && Article.from_h(e["article"]).canonical_url == canonical_url }
end

    def remember(article, judgment:, excerpt_used:)
      entry = (@entries[article.id] ||= { "first_seen_at" => Time.now.utc.iso8601, "shown_count" => 0 })
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

    def mark_shown(ids)
      ids.each { |id| @entries[id]["shown_count"] += 1 if @entries[id] }
    end

    def each_article
      @entries.each_value.map { |e| [Article.from_h(e["article"]), e] }
    end

    def prune!(now: Time.now)
      cutoff = now - RETENTION_DAYS * 86_400
      @entries.delete_if { |_, e| Time.parse(e["judged_at"] || e["first_seen_at"]) < cutoff }
    end

    def save
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate({ "updated_at" => Time.now.utc.iso8601, "articles" => @entries }))
    end
  end
end
