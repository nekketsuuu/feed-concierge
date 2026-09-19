# frozen_string_literal: true

require "time"

module FeedConcierge
  module Clock
    ZONE_SUFFIX = /(Z|[+-]\d{2}:?\d{2}|\b(UTC|GMT|[A-Z]{3,4}))\s*\z/

    module_function

    # Parses feed timestamps; a timestamp without a zone is taken as UTC, not the machine's zone.
    def parse(value)
      return value if value.is_a?(Time)

      text = value.to_s.strip
      text.match?(ZONE_SUFFIX) ? Time.parse(text) : Time.parse("#{text} UTC")
    end
  end
end
