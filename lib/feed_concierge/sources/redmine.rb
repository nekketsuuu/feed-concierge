# frozen_string_literal: true

require "json"
require "uri"

module FeedConcierge
  module Sources
    # Tickets on a Redmine instance (e.g. bugs.ruby-lang.org) that had any activity recently.
    # Uses the REST API with an updated_on filter; only the title and the top description are
    # kept, so the page is never fetched. published_at is the last activity time.
    class Redmine
      PAGE_SIZE = 100

      def initialize(name:, base_url:, lookback_days: 3, project_id: nil, description_max_chars: 1500)
        @name = name
        @base_url = base_url.chomp("/")
        @lookback_days = lookback_days
        @project_id = project_id
        @description_max_chars = description_max_chars
      end

      def articles
        since = (Time.now - (@lookback_days * 86_400)).utc.strftime("%Y-%m-%d")
        issues = []
        loop do
          page = JSON.parse(Http.get(issues_url(since, issues.size)))
          issues.concat(page.fetch("issues"))
          break if issues.size >= page.fetch("total_count") || page["issues"].empty?
        end
        issues.map { |issue| to_article(issue) }.sort_by { |a| -a.published_at.to_i }
      end

      private

      def issues_url(since, offset)
        params = { status_id: "*", updated_on: ">=#{since}", limit: PAGE_SIZE, offset: offset }
        params[:project_id] = @project_id if @project_id
        "#{@base_url}/issues.json?#{URI.encode_www_form(params)}"
      end

      def title_of(issue)
        state = issue.dig("status", "is_closed") ? "closed" : "open"
        "#{issue.dig('tracker', 'name')} ##{issue['id']}: #{issue['subject'].to_s.strip} (#{state})"
      end

      def to_article(issue)
        id = issue.fetch("id")
        Article.new(
          id: "#{@name}:#{id}",
          source: @name,
          title: title_of(issue),
          url: "#{@base_url}/issues/#{id}",
          author: issue.dig("author", "name"),
          published_at: Clock.parse(issue["updated_on"]),
          summary: issue["description"].to_s.strip[0, @description_max_chars],
          tags: [issue.dig("tracker", "name"), issue.dig("status", "name"), issue.dig("project", "name")].compact
        )
      end
    end
  end
end
