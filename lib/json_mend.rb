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
      # First, attempt to parse the string with the standard library.
      repaired_json = begin
        parsed = JSON.parse(
          json_string,
          allow_trailing_comma: true,
          allow_control_characters: true
        )

        # Verify the native parser didn't produce invalid UTF-8 (like unpaired surrogates)
        # by ensuring it can safely dump its own output.
        JSON.dump(parsed)

        parsed
      rescue JSON::ParserError, JSON::GeneratorError
        parser = Parser.new(json_string)
        parser.parse
      end

      # Avoids returning `null` for empty results, returns the object directly
      return repaired_json if return_objects

      # Always return a valid JSON string. For unparseable input, `nil` dumps to "null".
      JSON.dump(repaired_json)
    end
  end
end
