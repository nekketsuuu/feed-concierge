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
      return Time.parse(text) if text.match?(ZONE_SUFFIX)

      local = Time.parse(text)
      Time.utc(local.year, local.month, local.day, local.hour, local.min, local.sec)
    end
  end
end
