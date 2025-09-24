# frozen_string_literal: true

require 'strscan'
require 'json'

# Root module
module JsonMend
  # The core parser that does the heavy lifting of fixing the JSON.
  class Parser
    STRING_DELIMITERS = ['"', "'", '“', '”'].freeze

    def initialize(json_string)
      @scanner = StringScanner.new(json_string)
      @context = []
    end

    # Kicks off the parsing process. This is a direct port of the robust Python logic.
    def parse
      # Find and parse the first valid JSON value in the string.
      first_value = parse_value

      # If the scanner is at the end after the first parse, we're done.
      skip_whitespaces_and_comments
      return first_value if @scanner.eos?

      # If there's more, we're dealing with multiple concatenated JSON objects.
      all_values = [first_value]
      loop do
        skip_whitespaces_and_comments
        break if @scanner.eos?

        # Try to parse the next value
        next_val = parse_value

        if next_val.nil?
          # If we failed to parse (i.e., we hit garbage),
          # we must advance the scanner by one character to prevent an infinite loop.
          @scanner.getch unless @scanner.eos?
          next
        end

        # This logic correctly handles aggregation vs. replacement.
        if !all_values.empty? && same_object_type?(all_values.last, next_val)
          all_values.pop # Replace the last item
        end
        all_values << next_val
      end

      # Return a single value if only one was ultimately parsed, otherwise return the array.
      all_values.compact!
      all_values.length > 1 ? all_values : all_values.first
    end

    private

    # Main dispatcher for parsing any JSON value.
    def parse_value
      skip_whitespaces_and_comments
      case @scanner.peek(1)
      when '{' then parse_object
      when '[' then parse_array
      when *STRING_DELIMITERS then parse_string
      when 't', 'f', 'n', 'T', 'F', 'N' then parse_literal
      when ->(c) { c&.between?('0', '9') || c == '-' } then parse_number
      end
    end

    # Helper to check if two objects are of the same container type (Array or Hash).
    def same_object_type?(obj1, obj2)
      (obj1.is_a?(Array) && obj2.is_a?(Array)) || (obj1.is_a?(Hash) && obj2.is_a?(Hash))
    end

    # Parses a JSON object.
    def parse_object
      @scanner.getch # Consume '{'
      @context.push(:object)

      object = {}
      loop do
        skip_whitespaces_and_comments

        break if @scanner.peek(1) == '}' || @scanner.eos?

        key = parse_value
        # If the key is garbage, we can't continue parsing this object.
        break unless key

        skip_whitespaces_and_comments
        if @scanner.scan(':')
          value = parse_value
          object[key.to_s] = value
        else
          object[key.to_s] = true # Implicit true for keys without values
        end
        skip_whitespaces_and_comments
        break if @scanner.peek(1) == '}' || @scanner.eos?

        @scanner.scan(',')
      end
      @scanner.scan(/}/)
      @context.pop
      object
    end

    # Parses a JSON array.
    def parse_array
      @scanner.getch # Consume '['
      @context.push(:array)
      array = []
      loop do
        skip_whitespaces_and_comments
        break if @scanner.peek(1) == ']' || @scanner.eos?

        if @scanner.scan('...')
          @scanner.scan(',')
          next
        end

        value = parse_value
        # If we hit garbage inside an array, we stop parsing the array.
        break unless value

        array << value

        skip_whitespaces_and_comments
        break if @scanner.peek(1) == ']' || @scanner.eos?

        @scanner.scan(',')
      end
      @scanner.scan(/]/)
      @context.pop
      array
    end

    # Parses a string, handling both quoted and unquoted cases.
    def parse_string
      # Unquoted strings are not part of the JSON spec and are treated as garbage
      # by the main parse_value dispatcher. This method only handles quoted strings.
      quote = @scanner.peek(1)
      return nil unless STRING_DELIMITERS.include?(quote)

      @scanner.getch # consume opening quote
      buffer = +''
      loop do
        char = @scanner.getch
        break if char.nil?

        if char == '\\'
          buffer << char
          buffer << @scanner.getch unless @scanner.eos?
        elsif char == quote
          return buffer
        else
          buffer << char
        end
      end
      buffer # Unterminated string
    end

    # Parses a number (integer or float).
    def parse_number
      num_str = @scanner.scan(/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/)
      return nil unless num_str
      # If a number is followed by text, it's not a valid JSON number.
      return nil if @scanner.check(/[a-zA-Z]/)

      num_str.include?('.') || num_str.downcase.include?('e') ? num_str.to_f : num_str.to_i
    end

    # Parses true, false, or null from the scanner.
    def parse_literal
      if @scanner.check(/true/i)
        @scanner.scan(/true/i)
        true
      elsif @scanner.check(/false/i)
        @scanner.scan(/false/i)
        false
      elsif @scanner.check(/null/i)
        @scanner.scan(/null/i)
        nil
      end
    end

    # Skips whitespace and all comment types.
    def skip_whitespaces_and_comments
      loop do
        start_pos = @scanner.pos
        @scanner.scan(/\s+/)

        # Define terminators for line comments based on the current context
        terminators = '\n\r'
        terminators += '\]' if @context&.last == :array
        terminators += '\}' if @context&.last == :object

        # **FIX**: Line comments now correctly stop at context-specific terminators
        @scanner.scan(%r{//[^#{terminators}]*})
        @scanner.scan(/#[^#{terminators}]*/)
        @scanner.scan(%r{/\*.*?\*/})

        break if @scanner.pos == start_pos
      end
    end
  end
end
