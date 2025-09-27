# frozen_string_literal: true
require 'json'

require_relative 'json_mend/parser'
require_relative 'json_mend/version'

# Root module
module JsonMend
  class << self
    # Repairs a broken JSON string.
    #
    # @param json_string [String] The potentially broken JSON string.
    # @param return_objects [Boolean] If true, returns a Ruby object (Hash or Array), otherwise returns a valid JSON string.
    # @return [Object, String] The repaired JSON object or string.
    def repair(json_string, return_objects: false)
      parser = Parser.new(json_string)
      repaired_json = parser.parse
      # Avoids returning `null` for empty results, returns the object directly
      return repaired_json if return_objects

      # For string output, ensure we don't just return the string "null" for an empty input
      repaired_json.nil? ? '' : JSON.dump(repaired_json)
    end
  end
end
