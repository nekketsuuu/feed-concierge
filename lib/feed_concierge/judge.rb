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
    VERSION = 5
    # Bump one set's version to re-judge only the sources that use it (wording changes).
    SET_VERSIONS = { "advisory" => 3, "changelog" => 3 }.freeze

    INTEREST_LEVELS = [
      "The article is about a topic the reader profile explicitly says they are not interested in, or is unrelated to anything in the profile.",
      "The article is loosely adjacent to the reader's interests but the main topic is not one they listed.",
      "The article is about one of the reader's listed interests, in a general or introductory way.",
      "The article is squarely about one of the reader's listed interests.",
      "The article is centrally about a topic the reader lists as a favorite, or about several listed interests at once."
    ].freeze

    # Interest for changelog entries is about the service and the change, not the prose: the
    # article rubric above rewards depth and style that an announcement can never have.
    CHANGE_INTEREST_LEVELS = [
      "The product or service is one the reader would not use, or the change is irrelevant to the way they build and operate software.",
      "The service is one the reader might use, but the change does not affect how they build or operate: an unrelated region, a tier they would not buy, or a marketing or partner announcement.",
      "The service is one the reader likely uses, and the change is minor: an incremental option, a small integration, or a platform variant they may not run.",
      "The service is one the reader uses, and the change is practical for them: a new capability, a lifted limit, a changed default, an integration they would adopt, or a fix to something they rely on.",
      "The change directly alters something the reader depends on today in a core service: pricing or limits, deprecations, security defaults, or a long-requested capability."
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

    ADOPTION_LEVELS = [
      "A niche or little-known package, plugin, or product with a small user base.",
      "Known within its ecosystem but not a common dependency; used by a moderate number of projects.",
      "A widely used dependency, tool, or product that many applications rely on directly or transitively.",
      "Ubiquitous: an operating system, a major runtime, or a library present in most deployments."
    ].freeze

    COMPONENT_KINDS = {
      os_or_kernel: "An operating system, kernel, or base system component such as a libc, shell, or init system.",
      language_runtime_or_package: "A programming language runtime or a package from a language ecosystem such as a gem, npm package, or PyPI package.",
      library_dependency: "A general-purpose library that applications link or embed, such as image, media, compression, TLS, XML, or database client libraries.",
      server_software: "A database, cache, web server, message broker, mail server, or other server software that applications run alongside.",
      cloud_platform: "A cloud provider's service, agent, SDK, or managed runtime that production workloads run on, such as compute, storage, database, identity, or fleet-management services.",
      dev_tooling: "A container or orchestration tool, CI system, source hosting, editor, coding agent, or other developer tooling.",
      network_appliance: "A router, firewall, VPN gateway, email gateway, or other network appliance.",
      enterprise_or_consumer_product: "An enterprise application, industrial or medical system, consumer device, or mobile phone firmware."
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
      # Advisories (CVE catalog entries, weekly report items) have no prose to rate, so instead of
      # interest and substance they are judged on whether they touch the reader's stack and on the
      # kind of component that is affected.
      "advisory" => {
        affects_stack: {
          type: "noul",
          instructions: "Does the vulnerability in `article` affect software that the developer described in `reader_profile` runs or depends on?",
          criteria: {
            "true" => "The affected product is something that developer plausibly has in production or on a workstation: the operating system or kernel; Ruby, a gem, or a library Rails depends on; an npm package that a Ruby on Rails application commonly uses for its frontend or asset build (JavaScript frameworks, bundlers, CSS tooling, HTML or Markdown processing); a pip package commonly used to build API or web applications (web frameworks, HTTP servers and clients, async runtimes, validation, ORMs, task queues); mobile SDKs; a common database or server; a cloud service; or a mainstream developer tool.",
            "false" => "The affected product is network equipment, an enterprise or industrial product, a consumer device, an npm or pip package for a domain that developer does not work in (for example IoT, industrial protocols, blockchain, data science notebooks, desktop or game tooling, or a CMS plugin), or software that developer would not operate."
          }
        },
        component_kind: {
          type: "choice",
          instructions: "What kind of component does the vulnerability in `article` affect?",
          criteria: COMPONENT_KINDS
        },
        adoption: {
          type: "score",
          instructions: "How widely used is the software affected by the vulnerability in `article`?",
          criteria: ADOPTION_LEVELS
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
          instructions: "How much does the change announced in `article` matter to the reader described in `reader_profile`?",
          criteria: CHANGE_INTEREST_LEVELS
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
      judgment = { "model" => response["model"], "question_set" => question_set, "version" => VERSION,
                   "set_version" => SET_VERSIONS.fetch(question_set, 1), "tags" => {} }
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

    # True when a cached judgment answers every question in the named set, so a set whose
    # questions changed is re-judged without a VERSION bump.
    def self.complete?(judgment, question_set)
      return false unless (judgment["set_version"] || 1) == SET_VERSIONS.fetch(question_set, 1)

      QUESTION_SETS.fetch(question_set).all? do |id, question|
        next false unless judgment.key?(id.to_s)
        next true unless question[:type] == "choice"

        question[:criteria].keys.map(&:to_s).all? { |option| judgment.dig("#{id}_probabilities", option) }
      end
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
