# frozen_string_literal: true

require "cgi"

module FeedConcierge
  module Sources
    # Release notes are bullet lists whose version-only titles say nothing, so Jev picks the
    # changes worth catching up on and they become the title. Including sources set @name,
    # @product, @client, @min_probability, and @max_picks.
    module ReleaseNotes
      LABEL = /\A(?:\[[A-Z]+\]\s*|(?:feature|enhancement|bug ?fix|fix|change|misc|security)\s*[-:–]\s*)+/i
      HEADLINE_CHARS = 50

      private

      def release_article(id:, version:, url:, published_at:, bullets:, note: nil)
        picks = bullets.empty? ? [] : pick(bullets)
        title = "#{@product} #{version}: #{picks.empty? ? describe(bullets) : picks.map { |b| headline(b) }.join(' · ')}"
        rest = bullets.size - picks.size
        lines = picks.map { |b| "- #{b}" }
        lines << "…and #{rest} more #{rest == 1 ? 'change' : 'changes'}" if rest.positive?
        lines.unshift(note) if note
        Article.new(id: id, source: @name, title: title, url: url, published_at: published_at,
                    summary: lines.join("\n")[0, 1500])
      end

      # One Noul per bullet, all in one request; the bullets above the threshold become the title.
      def pick(bullets)
        changes = bullets.each_with_index.to_h { |b, i| ["c#{i}", b] }
        questions = bullets.each_index.to_h do |i|
          ["catchup_c#{i}", {
            type: "noul",
            instructions: "Is `release.changes.c#{i}` a change the reader described in `reader_profile` should catch up on: " \
                          "something that changes how they use the tool, a new capability, or a changed default?",
            criteria: {
              "true" => "A new capability, a changed default or behaviour, a removal or deprecation, or a fix to something the reader likely hits every day.",
              "false" => "A fix for a rare crash or edge case, an internal or enterprise-only detail, a change only in an editor extension, or a cosmetic change."
            }
          }]
        end
        state = { reader_profile: FeedConcierge.reader_profile, release: { product: @product, changes: changes } }
        answers = @client.system_one(state: state, questions: questions).fetch("answers")
        bullets.each_index.map { |i| [answers.dig("catchup_c#{i}", "noul").to_f, i] }
               .select { |p, _| p >= @min_probability }
               .sort_by { |p, i| [-p, i] }
               .first(@max_picks)
               .sort_by(&:last)
               .map { |_, i| bullets[i] }
      end

      # The first clause of a bullet without its links, issue numbers, and category label; a
      # short "component:" prefix stays, a long "Added X:" deed drops what follows the colon.
      def headline(bullet)
        head = clean(bullet).sub(LABEL, "").split(/[;(]| — | - |\. /, 2).first.to_s
        label, rest = head.split(":", 2)
        head = label if rest && label.split.size > 3
        head = head.strip.delete_suffix(".")
        return head if head.size <= HEADLINE_CHARS

        cut = head[0, HEADLINE_CHARS]
        cut = cut.sub(/\s+\S*\z/, "") unless head[HEADLINE_CHARS].match?(/\s/) || !cut.include?(" ")
        cut
      end

      def clean(bullet)
        bullet.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
              .gsub(/\s*by @[\w-]+ in \S+/, "")
              .gsub(%r{https?://\S+}, "")
              .gsub(/\s*\((?:Bug|WL) #?\d+\)/i, "")
              .gsub(/\s*\(?#\d+\)?/, "")
              .delete("*`")
              .gsub(/\s+/, " ").strip
      end

      def describe(bullets)
        return "no listed changes" if bullets.empty?

        noun = bullets.all? { |b| b.start_with?("Fixed") } ? "fix" : "change"
        "#{bullets.size} #{noun}#{'s' unless bullets.size == 1}"
      end

      def text(html)
        CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s*§/, "").gsub(/\s+/, " ").strip
      end
    end
  end
end
