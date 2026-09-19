module FeedConcierge
  # Combines Jev's answers with freshness and exposure. Every number here is
  # code-owned so weights can be tuned without re-querying Jev.
  class Ranker
    Ranked = Struct.new(:article, :entry, :relevance, :freshness, :exposure, :score, :age_hours, keyword_init: true)

    def initialize(config, now: Time.now)
      @config = config
      @now = now
    end

    def rank(store)
      ranked = store.each_article.map { |article, entry| evaluate(article, entry) }
      ranked.select { |r| r.relevance >= @config["min_relevance"] }
            .sort_by { |r| -r.score }
            .uniq { |r| r.article.canonical_url }
            .then { |list| cap_per_source(list) }
            .first(@config["top_n"])
    end

    def evaluate(article, entry)
      j = entry["judgment"]
      relevance = relevance_of(j)
      age_hours = [(@now - article.published_at) / 3600.0, 0].max
      freshness = freshness_of(age_hours, evergreen: j["evergreen"].to_f)
      exposure = @config["exposure_decay"]**entry["shown_count"].to_i
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
  end
end
