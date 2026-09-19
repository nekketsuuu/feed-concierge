module FeedConcierge
  class Pipeline
    def initialize(settings: FeedConcierge.settings, store_path:, output_dir:, client:, logger: $stderr)
      @settings = settings
      @store = Store.new(store_path)
      @output_dir = output_dir
      @judge = Judge.new(client)
      @skip_excerpt = Sources.without_excerpt(settings["sources"])
      @log = logger
    end

    def run
      articles = Sources.fetch_all(@settings["sources"], logger: @log)
      @log.puts "fetched #{articles.size} articles"

      pending = articles.reject { |a| @store.judged?(a.id) || @store.judged_url?(a.canonical_url) }
      articles.each { |a| @store.refresh_stats(a) }
      judge_all(pending)

      @store.prune!
      ranked = Ranker.new(@settings["ranking"]).rank(@store)
      Site.new(@output_dir, title: @settings.dig("site", "title"), source_labels: @settings.dig("site", "source_labels") || {}).build(
        ranked, generated_at: Time.now, judged_count: @store.each_article.size
      )
      @store.mark_shown(ranked.map { |r| r.article.id })
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
              results << [article, excerpt, @judge.judge(article, excerpt: excerpt, reader_profile: profile)]
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
        @log.puts format("  %-60.60s interest=%.2f worth=%.2f", article.title, judgment["interest"].to_f, judgment["worth_reading"].to_f)
      end
    end

    def fetch_excerpt(article)
      cfg = @settings["article_excerpt"]
      return nil unless cfg["enabled"] && !@skip_excerpt.include?(article.source)

      Excerpt.fetch(article.url, max_chars: cfg["max_chars"], timeout: cfg["timeout_seconds"])
    end
  end
end
