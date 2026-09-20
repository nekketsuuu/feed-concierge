# frozen_string_literal: true

module FeedConcierge
  # Combines Jev's answers with freshness. Every number here is code-owned
  # so weights can be tuned without re-querying Jev.
  class Ranker
    Ranked = Data.define(:article, :entry, :relevance, :components, :freshness, :score, :age_hours)

    def initialize(config, now: Time.now)
      @config = config
      @now = now
    end

    def rank(store)
      page_from(candidates(store))
    end

    # Every judged article that clears min_relevance, best first; the tune page re-ranks these.
    def candidates(store)
      store.each_article.map { |article, entry| evaluate(article, entry) }
           .select { |r| r.relevance >= @config["min_relevance"] }
           .sort_by { |r| -r.score }
    end

    # Applies the page rules to sorted candidates: score threshold, one entry per CVE or URL,
    # per-source caps, and the overall cap.
    def page_from(candidates)
      candidates.select { |r| r.score >= @config["min_score"] }
                .uniq { |r| r.article.dedup_key }
                .then { |list| cap_per_source(list) }
                .first(@config["top_n"])
    end

    def evaluate(article, entry)
      j = entry["judgment"]
      components = components_of(j)
      relevance = components.sum { |c| c[:contribution] }
      age_hours = [(@now - article.published_at) / 3600.0, 0].max
      freshness = freshness_of(age_hours, evergreen: j["evergreen"].to_f)
      Ranked.new(article: article, entry: entry, relevance: relevance, components: components, freshness: freshness,
                 score: relevance * freshness, age_hours: age_hours)
    end

    # How freshness was derived, plus what-if values, for the tune page.
    def explain(item)
      f = @config["freshness"]
      evergreen = item.entry.dig("judgment", "evergreen").to_f
      {
        freshness: {
          age_hours: item.age_hours.round, evergreen: evergreen.round(2),
          half_life_hours: (f["half_life_hours"] + (f["evergreen_half_life_bonus_hours"] * evergreen)).round,
          base_half_life_hours: f["half_life_hours"], bonus_hours: f["evergreen_half_life_bonus_hours"], floor: f["floor"],
          steepness: f["steepness"],
          if_evergreen_zero: freshness_of(item.age_hours, evergreen: 0.0).round(3),
          if_evergreen_one: freshness_of(item.age_hours, evergreen: 1.0).round(3)
        }
      }
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

    # One entry per weighted question: the normalized answer, its weight, and their product.
    def components_of(judgment)
      weights = @config["weights"].fetch(judgment["question_set"] || "default")
      weights.map do |id, weight|
        value = Judge.normalize(judgment, id, choice_weights: @config["choice_weights"] || {})
        { id: id, value: value, weight: weight, contribution: weight * value }
      end
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
