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
      values = []
      loop do
        skip_whitespaces_and_comments
        # Actively look for the start of a JSON object or array, skipping garbage text.
        start = @scanner.scan_until(/[{\[]/)
        unless start
          # Only try to parse a primitive if we haven't found any other values yet
          if values.empty?
            @scanner.reset
            val = parse_value
            values << val if val
          end
          break
        end

        @scanner.pos -= 1 # Rewind to include the '{' or '['

        new_value = parse_value
        next if new_value.nil?

        values.pop if !values.empty? && same_object_type?(values.last, new_value)
        values << new_value
      end

      values.length > 1 ? values : values.first
    end

    private

    def parse_value_from_anywhere
      start = @scanner.scan_until(/[\[{"'\d\-.\\tfcnTFN]/)
      return nil unless start

      @scanner.pos -= 1 # Rewind to include the valid starting character
      parse_value
    end

    # Main dispatcher for parsing any JSON value.
    def parse_value
      skip_whitespaces_and_comments
      case @scanner.peek(1)
      when '{' then parse_object
      when '[' then parse_array
      when *STRING_DELIMITERS then parse_string
      when ->(c) { c&.between?('0', '9') || c == '-' || c == '.' } then parse_number
      when 't', 'f', 'n', 'T', 'F', 'N' then parse_literal
      else
        parse_unquoted_string
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
        object[key.to_s] = if @scanner.scan(':')
                             parse_value
                           else
                             true # Implicit true for keys without values
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

    # Parses a quoted string.
    def parse_string
      quote = @scanner.peek(1)
      return nil unless STRING_DELIMITERS.include?(quote)

      @scanner.getch
      buffer = +''
      loop do
        char = @scanner.getch
        break if char.nil?

        if char == '\\'
          buffer << char
          buffer << @scanner.getch unless @scanner.eos?
        elsif (quote == '“' && char == '”') || char == quote
          return buffer
        else
          buffer << char
        end
      end
      buffer
    end

    # **FIXED**: Parses an unquoted string value robustly.
    def parse_unquoted_string
      buffer = +''
      loop do
        break if @scanner.eos?

        char = @scanner.peek(1)

        terminators = [',', '}', ']']
        # A colon terminates a key, but can be part of a value
        terminators << ':' if @context.last == :object

        break if terminators.include?(char)

        # Break on whitespace only if it's not between words
        if char.strip.empty? && !buffer.empty?
          # Peek ahead to see if the next non-whitespace char is a terminator
          next_char_pos = @scanner.pos + 1
          next_char_pos += 1 while @scanner.string[next_char_pos]&.strip&.empty?
          next_non_ws = @scanner.string[next_char_pos]
          break if next_non_ws.nil? || terminators.include?(next_non_ws)
        elsif char.strip.empty?
          break
        end

        buffer << @scanner.getch
      end

      literal = parse_literal_from_string(buffer)
      return literal unless literal.nil?

      buffer.strip
    end

    # Parses true, false, or null from a string (for unquoted values).
    def parse_literal_from_string(str)
      s = str.strip.downcase
      case s
      when 'true' then true
      when 'false' then false
      when 'null' then nil
      end
    end

    # Parses a number (integer or float).
    def parse_number
      number_result = []

      # Greedily consume all characters that could be part of a number or number-like string
      loop do
        break if @scanner.eos?

        char = @scanner.peek(1)
        break if char.nil?
        break if char == ',' && current_context == :array

        break unless '0123456789-.eE/,'.include?(char)

        number_result << @scanner.getch
      end

      # Roll back if the string ends with an invalid character
      if !number_result.empty? && '-eE/,'.include?(number_result[-1])
        number_result.pop
        @scanner.pos -= 1
      end

      return nil if number_result.empty?

      # If the number is immediately followed by other characters, it's part of a string
      if @scanner.check(/[a-zA-Z]/)
        number_result << @scanner.scan(/[a-zA-Z0-9]*/)
        return number_result.join
      end

      # Attempt to convert to a number, falling back to a string if it fails
      begin
        if number_result.include?('/') || number_result.count { it == '.' } > 1 || number_result.count do
          it == '-'
        end > 1
          number_result.join&.to_s # Treat as a string
        elsif number_result.include?('.') || number_result.find { it&.downcase == 'e' }
          Float(number_result.join)
        else
          Integer(number_result.join)
        end
      rescue ArgumentError
        number_result.join
      end
    end

    # Parses true, false, or null from the scanner.
    def parse_literal
      if @scanner.scan(/true/i)
        true
      elsif @scanner.scan(/false/i)
        false
      elsif @scanner.scan(/null/i)
        nil
      end
    end

    # Skips whitespace and all comment types.
    def skip_whitespaces_and_comments
      loop do
        start_pos = @scanner.pos
        @scanner.scan(/\s+/)
        if @scanner.check(%r{/[/*#]})
          if @scanner.check(%r{/\*})
            @scanner.scan_until(%r{\*/})
          elsif @scanner.scan(%r{//}) || @scanner.scan(/#/)
            loop do
              char = @scanner.peek(1)
              break if char.nil?
              terminators = ["\n", "\r"]
              terminators << "}" if current_context == :object
              terminators << "]" if current_context == :array
              break if terminators.include?(char)
              @scanner.getch
            end
          end
        end
        break if @scanner.pos == start_pos
      end
    end

    def current_context
      @context&.last
    end
  end
end
