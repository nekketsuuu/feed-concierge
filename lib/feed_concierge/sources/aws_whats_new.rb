# frozen_string_literal: true

module FeedConcierge
  module Sources
    # AWS What's New; a region expansion that reaches Tokyo says so in its title.
    class AwsWhatsNew < Rss
      REGION_NAME = /US|Europe|Asia Pacific|Canada|South America|Middle East|Africa|Israel|Mexico|GovCloud/
      REGION_EXPANSION = /\bregions?\b|available in (?:the )?(?:AWS )?#{REGION_NAME}/i
      TOKYO = /Asia Pacific \(Tokyo\)|ap-northeast-1/

      private

      def to_article(item)
        article = super
        return article unless article && article.title.match?(REGION_EXPANSION) && !article.title.match?(TOKYO) &&
                              body_of(item).match?(TOKYO)

        article.with(title: "#{article.title} (Tokyo)")
      end
    end
  end
end
