require "json"
require "yaml"
require "time"

module HnConcierge
  ROOT = File.expand_path("..", __dir__)

  def self.settings
    @settings ||= YAML.safe_load_file(File.join(ROOT, "config", "settings.yml"))
  end

  def self.reader_profile
    File.read(File.join(ROOT, "config", "profile.md")).strip
  end
end

require_relative "hn_concierge/feed"
require_relative "hn_concierge/excerpt"
require_relative "hn_concierge/jev_client"
require_relative "hn_concierge/judge"
require_relative "hn_concierge/store"
require_relative "hn_concierge/ranker"
require_relative "hn_concierge/site"
require_relative "hn_concierge/pipeline"
