module FeedConcierge
  # Combines Jev's answers with freshness, popularity, and exposure. Every number here is
  # code-owned so weights can be tuned without re-querying Jev.
  class Ranker
    Ranked = Struct.new(:article, :entry, :relevance, :freshness, :popularity, :exposure, :score, :age_hours,
                        keyword_init: true)

    def initialize(config, now: Time.now)
      @config = config
      @now = now
    end

    def rank(store)
      ranked = store.each_article.map { |article, entry| evaluate(article, entry) }
      ranked.select { |r| r.relevance >= @config["min_relevance"] }
            .sort_by { |r| -r.score }
            .uniq { |r| r.article.canonical_url }
            .first(@config["top_n"])
    end

    def evaluate(article, entry)
      j = entry["judgment"]
      relevance = relevance_of(j)
      age_hours = [(@now - article.published_at) / 3600.0, 0].max
      freshness = freshness_of(age_hours, evergreen: j["evergreen"].to_f)
      popularity = popularity_of(article)
      exposure = @config["exposure_decay"]**entry["shown_count"].to_i
      Ranked.new(article: article, entry: entry, relevance: relevance, freshness: freshness,
                 popularity: popularity, exposure: exposure, age_hours: age_hours,
                 score: relevance * freshness * popularity_factor(popularity) * exposure)
    end

    private

    def relevance_of(j)
      w = @config["weights"]
      w["interest"] * (j["interest"].to_f / Judge.interest_max) +
        w["substance"] * (j["substance"].to_f / Judge.substance_max) +
        w["worth_reading"] * j["worth_reading"].to_f
    end

    def freshness_of(age_hours, evergreen:)
      f = @config["freshness"]
      half_life = f["half_life_hours"] + f["evergreen_half_life_bonus_hours"] * evergreen
      f["floor"] + (1 - f["floor"]) * 2**(-age_hours / half_life)
    end

    def popularity_of(article)
      p = @config["popularity"]
      reference = p["reference_points"][article.source]
      return p["unknown"] unless reference && article.points

      [Math.log1p([article.points, 0].max) / Math.log1p(reference), 1.0].min
    end

    def popularity_factor(popularity)
      floor = @config.dig("popularity", "floor")
      floor + (1 - floor) * popularity
    end
  end
end
