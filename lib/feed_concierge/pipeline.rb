# frozen_string_literal: true

module FeedConcierge
  class Pipeline
    def initialize(settings: FeedConcierge.settings, store_path:, output_dir:, client:, logger: $stderr)
      @settings = settings
      @store = Store.new(store_path)
      @output_dir = output_dir
      @judge = Judge.new(client)
      @skip_excerpt = Sources.without_excerpt(settings["sources"])
      @question_sets = Sources.question_sets(settings["sources"])
      @log = logger
    end

    def run
      articles = Sources.fetch_all(@settings["sources"], logger: @log)
      @log.puts "fetched #{articles.size} articles"

      pending = articles.reject do |a|
        @store.judged?(a.id, question_set: question_set_for(a)) || (@store[a.id].nil? && @store.judged_url?(a.canonical_url))
      end
      articles.each { |a| @store.refresh_stats(a) }
      judge_all(pending)

      @store.prune!(retention_days: @settings["retention_days"])
      ranked = Ranker.new(@settings["ranking"]).rank(@store)
      site = Site.new(@output_dir, site: @settings.fetch("site"), tag_config: @settings.fetch("tags"),
                                   ranking_config: @settings.fetch("ranking"))
      site.build(ranked, generated_at: Time.now, judged_count: @store.each_article.size)
      @store.save
      @log.puts "ranked #{ranked.size} articles -> #{@output_dir}"
      ranked
    end

    private

    def judge_all(articles)
      @log.puts "judging #{articles.size} new articles"
      profile = FeedConcierge.reader_profile
      queue = Queue.new
      articles.each { |a| queue << a }
      queue.close
      results = Queue.new

      workers = Array.new(@settings["concurrency"]) do
        Thread.new do
          while (article = queue.pop)
            begin
              excerpt = fetch_excerpt(article)
              judgment = @judge.judge(article, excerpt: excerpt, reader_profile: profile, question_set: question_set_for(article))
              results << [article, excerpt, judgment]
            rescue JevClient::Error => e
              @log.puts "  skipped #{article.id}: #{e.message}"
            end
          end
        end
      end
      workers.each(&:join)

      until results.empty?
        article, excerpt, judgment = results.pop
        @store.remember(article, judgment: judgment, excerpt_used: !excerpt.nil?)
        @log.puts format("  %-60.60s interest=%.2f worth=%.2f", article.title, judgment["interest"].to_f,
                         judgment["worth_reading"].to_f)
      end
    end

    def question_set_for(article)
      @question_sets.fetch(article.source, "default")
    end

    def fetch_excerpt(article)
      cfg = @settings["article_excerpt"]
      return nil unless cfg["enabled"] && !@skip_excerpt.include?(article.source)

      Excerpt.fetch(article.url, max_chars: cfg["max_chars"], timeout: cfg["timeout_seconds"])
    end
  end
end
