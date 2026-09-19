# frozen_string_literal: true

require "yaml"

module FeedConcierge
  # Asks Jev a fixed set of questions about one article. All questions go in one request
  # (speculative fan-out); code combines the answers later in Ranker.
  #
  # Question sets are chosen per source (config `questions:`). Answers are stored flat:
  # score -> <id>, <id>_confidence; noul -> <id>; choice -> <id>, <id>_probabilities.
  # Tag questions (one Noul per tag in config/tags.yml) are stored under "tags".
  class Judge
    # Bump when questions change so cached judgments are redone on the next build.
    VERSION = 4

    INTEREST_LEVELS = [
      "The article is about a topic the reader profile explicitly says they are not interested in, or is unrelated to anything in the profile.",
      "The article is loosely adjacent to the reader's interests but the main topic is not one they listed.",
      "The article is about one of the reader's listed interests, in a general or introductory way.",
      "The article is squarely about one of the reader's listed interests and matches the kind of content they say they enjoy.",
      "The article is exactly the kind of piece the reader profile describes as a favorite: a listed topic treated in the listed style."
    ].freeze

    SUBSTANCE_LEVELS = [
      "A product page, press release, announcement, or link with little explanation of its own.",
      "A short news report or summary that relays facts without much analysis.",
      "An article that explains a subject with specific details, examples, or reasoning.",
      "An in-depth technical write-up, primary source, or original research with substantial detail."
    ].freeze

    TICKET_KINDS = {
      language_change: "Proposes or decides a change to the language's syntax, semantics, or a core class/method's public behaviour, including deprecations and new methods.",
      design_discussion: "Discusses the design, trade-offs, or direction of a feature or subsystem (for example a concurrency model, JIT, sandboxing, or garbage collector) rather than one concrete defect.",
      behavior_bug: "Reports incorrect results or surprising behaviour that a programmer could hit with ordinary code, without a crash.",
      crash_report: "Reports a crash, memory-safety error, or assertion failure, typically found by a fuzzer or with contrived code, and consists mostly of a proof-of-concept and a sanitizer or assertion trace.",
      build_platform: "Reports a build, compile, packaging, or platform-specific installation problem.",
      housekeeping: "Backport tracking, documentation wording, typos, test flakiness, release process, or other administrative work."
    }.freeze

    CHANGE_KINDS = {
      new_capability: "Introduces a new product, feature, API, or capability that did not exist before.",
      breaking_or_deprecation: "Announces a breaking change, deprecation, end of support, or a changed default that requires users to act.",
      pricing_or_limits: "Changes pricing, the free tier, quotas, or limits.",
      incremental_improvement: "Improves an existing feature: performance, UI, integrations, more options, or expanded support for versions and platforms.",
      regional_availability: "An existing feature or service becomes available in additional regions, countries, or data centres, with no new functionality.",
      fix_or_maintenance: "Bug fixes, security patches, version bumps, or documentation updates."
    }.freeze

    PR_KINDS = {
      new_feature: "Adds a new public API, option, generator, or capability that users of the framework can call or configure.",
      behavior_change_or_deprecation: "Changes existing public behaviour or defaults, deprecates or removes something, or requires users to adjust when upgrading.",
      performance: "Makes existing behaviour faster or lighter on memory without changing what it does.",
      bug_fix: "Fixes incorrect behaviour that users could hit, without adding new capabilities.",
      internal_refactor: "Restructures, cleans up, or renames internal code with no user-visible effect.",
      docs_tests_ci: "Documentation, comments, tests, CI configuration, dependency bumps, or release chores."
    }.freeze

    USER_IMPACT_LEVELS = [
      "Only affects contrived code, fuzzer inputs, or an internal detail no ordinary program touches.",
      "Affects a specific niche: one platform, one rarely used method, or an unusual configuration.",
      "Affects a commonly used method, class, or idiom that many programs rely on.",
      "Affects nearly every program: core syntax, object model, threading, or a project-wide rule."
    ].freeze

    WORTH_READING = {
      type: "noul",
      instructions: "Would the person described in `reader_profile` be glad they opened `article`?",
      criteria: {
        "true" => "The reader would find it worth their time based on their stated interests.",
        "false" => "The reader would consider it a waste of time or outside their interests."
      }
    }.freeze

    EVERGREEN = {
      type: "noul",
      instructions: "Will `article` still be worth reading a month from now?",
      criteria: {
        "true" => "The content is explanatory, technical, or timeless; its value does not depend on being current.",
        "false" => "The content is breaking news, a time-limited event, or a status update that goes stale quickly."
      }
    }.freeze

    QUESTION_SETS = {
      "default" => {
        interest: {
          type: "score",
          instructions: "How well does `article` match the interests described in `reader_profile`?",
          criteria: INTEREST_LEVELS
        },
        substance: {
          type: "score",
          instructions: "How substantive is the content of `article`, judging from its title, source, and excerpt?",
          criteria: SUBSTANCE_LEVELS
        },
        worth_reading: WORTH_READING,
        evergreen: EVERGREEN
      },
      "changelog" => {
        change_kind: {
          type: "choice",
          instructions: "`article` is an entry from a product changelog or announcement feed. Which kind of change does it announce?",
          criteria: CHANGE_KINDS
        },
        interest: {
          type: "score",
          instructions: "How well does the change announced in `article` match the interests described in `reader_profile`?",
          criteria: INTEREST_LEVELS
        },
        worth_reading: WORTH_READING,
        evergreen: EVERGREEN
      },
      "pull_request" => {
        pr_kind: {
          type: "choice",
          instructions: "`article` is a merged pull request (title, labels, and description). Which kind of change is it?",
          criteria: PR_KINDS
        },
        user_impact: {
          type: "score",
          instructions: "How much of the project's user base would notice the change described in `article` after upgrading?",
          criteria: USER_IMPACT_LEVELS
        },
        interest: {
          type: "score",
          instructions: "How well does the change in the pull request `article` match the interests described in `reader_profile`?",
          criteria: INTEREST_LEVELS
        },
        worth_reading: WORTH_READING,
        evergreen: EVERGREEN
      },
      "ticket" => {
        kind: {
          type: "choice",
          instructions: "`article` is an issue-tracker ticket (title, tags, and its opening description). Which kind of ticket is it?",
          criteria: TICKET_KINDS
        },
        user_impact: {
          type: "score",
          instructions: "If the change or defect described in `article` is real, how much of the language's user base would notice it?",
          criteria: USER_IMPACT_LEVELS
        },
        interest: {
          type: "score",
          instructions: "How well does the subject of the ticket `article` match the interests described in `reader_profile`?",
          criteria: INTEREST_LEVELS
        },
        worth_reading: WORTH_READING,
        evergreen: EVERGREEN
      }
    }.freeze

    def self.tag_vocabulary
      @tag_vocabulary ||= YAML.safe_load_file(File.join(ROOT, "config", "tags.yml")).fetch("tags")
    end

    # One Noul per tag, asked alongside every question set. Probabilities are stored so the
    # display threshold can be tuned without re-judging.
    def self.tag_questions
      tag_vocabulary.to_h do |tag, description|
        ["tag_#{tag}", { type: "noul",
                         instructions: "Does the topic tag `#{tag}` apply to `article`?",
                         criteria: { "true" => "The article is substantially about: #{description}",
                                     "false" => "The article only mentions this in passing, or not at all." } }]
      end
    end

    # Tags whose probability clears the threshold, most likely first.
    def self.tags_for(judgment, min_probability:, max:)
      (judgment["tags"] || {}).select { |_, p| p >= min_probability }.sort_by { |_, p| -p }.first(max).map(&:first)
    end

    def initialize(client)
      @client = client
    end

    def judge(article, excerpt:, reader_profile:, question_set: "default")
      questions = QUESTION_SETS.fetch(question_set).merge(self.class.tag_questions)
      state = {
        reader_profile: reader_profile,
        article: {
          title: article.title,
          source_domain: article.domain,
          found_via: article.source,
          tags: article.tags,
          points: article.points,
          comments: article.comment_count,
          summary: article.summary,
          excerpt: excerpt
        }.compact
      }
      response = @client.system_one(state: state, questions: questions)
      answers = response.fetch("answers")
      judgment = { "model" => response["model"], "question_set" => question_set, "version" => VERSION, "tags" => {} }
      questions.each_key do |id|
        answer = answers.fetch(id.to_s)
        if id.to_s.start_with?("tag_")
          judgment["tags"][id.to_s.delete_prefix("tag_")] = answer["noul"]
          next
        end
        case answer["type"]
        when "score"
          judgment[id.to_s] = answer["score"]
          judgment["#{id}_confidence"] = answer["confidence"]
        when "noul"
          judgment[id.to_s] = answer["noul"]
        when "choice"
          judgment[id.to_s] = answer["choice"]
          judgment["#{id}_probabilities"] = answer["probabilities"]
        end
      end
      judgment.merge("input_tokens" => response.dig("usage", "input_tokens"))
    end

    # Maps a stored answer to 0..1 so Ranker can weight questions uniformly.
    # Choice answers need per-option weights from config.
    def self.normalize(judgment, id, choice_weights: {})
      question = QUESTION_SETS.fetch(judgment["question_set"] || "default").fetch(id.to_sym)
      case question[:type]
      when "score" then judgment[id].to_f / (question[:criteria].size - 1)
      when "noul" then judgment[id].to_f
      when "choice"
        weights = choice_weights.fetch(id)
        judgment["#{id}_probabilities"].sum { |option, p| p * weights.fetch(option, 0.0) }
      end
    end
  end
end
