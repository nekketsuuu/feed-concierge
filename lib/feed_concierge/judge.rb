module FeedConcierge
  # Asks Jev a fixed set of questions about one article. All questions go in one request
  # (speculative fan-out); code combines the answers later in Ranker.
  class Judge
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

    def initialize(client)
      @client = client
    end

    def questions
      {
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
        worth_reading: {
          type: "noul",
          instructions: "Would the person described in `reader_profile` be glad they opened `article`?",
          criteria: {
            true: "The reader would find it worth their time based on their stated interests.",
            false: "The reader would consider it a waste of time or outside their interests."
          }
        },
        evergreen: {
          type: "noul",
          instructions: "Will `article` still be worth reading a month from now?",
          criteria: {
            true: "The content is explanatory, technical, or timeless; its value does not depend on being current.",
            false: "The content is breaking news, a time-limited event, or a status update that goes stale quickly."
          }
        }
      }
    end

    def judge(article, excerpt:, reader_profile:)
      state = {
        reader_profile: reader_profile,
        article: {
          title: article.title,
          source_domain: article.domain,
          points: article.points,
          comments: article.comment_count,
          excerpt: excerpt
        }.compact
      }
      response = @client.system_one(state: state, questions: questions)
      answers = response.fetch("answers")
      {
        "model" => response["model"],
        "interest" => answers.dig("interest", "score"),
        "interest_confidence" => answers.dig("interest", "confidence"),
        "substance" => answers.dig("substance", "score"),
        "substance_confidence" => answers.dig("substance", "confidence"),
        "worth_reading" => answers.dig("worth_reading", "noul"),
        "evergreen" => answers.dig("evergreen", "noul"),
        "input_tokens" => response.dig("usage", "input_tokens")
      }
    end

    def self.interest_max = INTEREST_LEVELS.size - 1
    def self.substance_max = SUBSTANCE_LEVELS.size - 1
  end
end
