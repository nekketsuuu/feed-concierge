# frozen_string_literal: true

require "json"
require "yaml"
require "time"

module FeedConcierge
  ROOT = File.expand_path("..", __dir__)

  def self.settings
    @settings ||= YAML.safe_load_file(File.join(ROOT, "config", "settings.yml"))
  end

  def self.reader_profile
    File.read(File.join(ROOT, "config", "profile.md")).strip
  end
end

require_relative "feed_concierge/article"
require_relative "feed_concierge/sources"
require_relative "feed_concierge/excerpt"
require_relative "feed_concierge/jev_client"
require_relative "feed_concierge/judge"
require_relative "feed_concierge/store"
require_relative "feed_concierge/ranker"
require_relative "feed_concierge/site"
require_relative "feed_concierge/pipeline"
