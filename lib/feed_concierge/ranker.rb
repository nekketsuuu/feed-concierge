# frozen_string_literal: true

module FeedConcierge
  # Combines Jev's answers with freshness and exposure. Every number here is code-owned
  # so weights can be tuned without re-querying Jev.
  class Ranker
    Ranked = Data.define(:article, :entry, :relevance, :freshness, :exposure, :score, :age_hours)

    def initialize(config, now: Time.now)
      @config = config
      @now = now
    end

    def rank(store)
      ranked = store.each_article.map { |article, entry| evaluate(article, entry) }
      ranked.select { |r| r.relevance >= @config["min_relevance"] && r.score >= @config["min_score"] }
            .sort_by { |r| -r.score }
            .uniq { |r| r.article.dedup_key }
            .then { |list| cap_per_source(list) }
            .first(@config["top_n"])
    end

    def evaluate(article, entry)
      j = entry["judgment"]
      relevance = relevance_of(j)
      age_hours = [(@now - article.published_at) / 3600.0, 0].max
      freshness = freshness_of(age_hours, evergreen: j["evergreen"].to_f)
      exposure = exposure_of(entry)
      Ranked.new(article: article, entry: entry, relevance: relevance, freshness: freshness,
                 exposure: exposure, score: relevance * freshness * exposure, age_hours: age_hours)
    end

    def cap_per_source(list)
      limits = @config["max_per_source"] || {}
      counts = Hash.new(0)
      list.select do |r|
        limit = limits[r.article.source]
        next true unless limit

        (counts[r.article.source] += 1) <= limit
      end
    end

    private

    def relevance_of(judgment)
      weights = @config["weights"].fetch(judgment["question_set"] || "default")
      weights.sum { |id, w| w * Judge.normalize(judgment, id, choice_weights: @config["choice_weights"] || {}) }
    end

    # Halves every exposure_half_life_days after the article first appeared on the page.
    def exposure_of(entry)
      first_shown = entry["first_shown_at"] or return 1.0
      days_shown = [(@now - Time.parse(first_shown)) / 86_400.0, 0].max
      0.5**(days_shown / @config["exposure_half_life_days"])
    end

    # A logistic curve in age: flat for the first day or so, halfway down at half_life_hours,
    # then a long tail. Evergreen articles get a longer half-life.
    def freshness_of(age_hours, evergreen:)
      f = @config["freshness"]
      half_life = f["half_life_hours"] + (f["evergreen_half_life_bonus_hours"] * evergreen)
      f["floor"] + ((1 - f["floor"]) / (1 + ((age_hours / half_life)**f["steepness"])))
    end
  end
end
