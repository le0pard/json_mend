# frozen_string_literal: true

require 'strscan'
require 'set'

# Root module
module JsonMend
  # The core parser that does the heavy lifting of fixing the JSON.
  class Parser
    COMMENT_DELIMETERS = ['#', '/'].freeze
    NUMBER_CHARS = Set.new("0123456789-.eE/,".chars).freeze
    STRING_DELIMITERS = ['"', "'", '“', '”'].freeze

    def initialize(json_string)
      @scanner = StringScanner.new(json_string)
      @context = []
    end

    # Kicks off the parsing process. This is a direct port of the robust Python logic.
    def parse
      json = parse_json

      unless @scanner.eos?
        json = [json]
        while !@scanner.eos?
          j = parse_json
          if j != ""
            json.pop if same_object_type?(json.last, j)
            json << j
          else
            @scanner.pos += 1
          end
        end

        json = json.length > 1 ? json : json.first
      end

      json
    end

    private

    def parse_json
      until @scanner.eos?
        case @scanner.peek(1)
        when '{'
          @scanner.pos += 1 # consume '{'
          return parse_object
        when '['
          @scanner.pos += 1 # consume '['
          return parse_array
        when ->(c) { STRING_DELIMITERS.include?(c) || c&.match?(/[a-zA-Z]/) }
          return parse_string
        when ->(c) { c&.match?(/\d/) || c == '-' || c == '.' }
          return parse_number
        when *COMMENT_DELIMETERS
          return parse_comment
        else
          @scanner.pos += 1
        end
      end
    end

    # Parses a JSON object.
    def parse_object
      object = {}
      while !@scanner.scan('}') && !@scanner.eos?
        skip_whitespaces

        # Sometimes LLMs do weird things, if we find a ":" so early, we'll change it to "," and move on
        @scanner.scan(':')

        # We are now searching for they string key
        # Context is used in the string parser to manage the lack of quotes
        @context.push(:object_key)

        # Save this index in case we need find a duplicate key
        rollback_index = @scanner.pos

        # --- Key Parsing ---
        key = ''
        while !@scanner.eos?
          rollback_index = @scanner.pos # Update rollback position
          # Is this an array?
          # Need to check if the previous parsed value contained in obj is an array and in that case parse and merge the two
          if key.empty? && @scanner.peek(1) == '['
            prev_key = object.keys.last
            if prev_key && obj[prev_key].is_a?(Array)
              @scanner.pos += 1 # consume '['
              new_array = parse_array
              if new_array.is_a?(Array)
                to_merge = new_array.length == 1 && new_array[0].is_a?(Array) ? new_array[0] : new_array
                object[prev_key].concat(to_merge)

                skip_whitespaces

                @scanner.scan(',') # consume optional comma
                skip_whitespaces

                was_array_merged = true
                next
              end
            end
          end

          key = parse_string.to_s
          skip_whitespaces if key.empty?

          # If the string is empty but there is a object divider, we are done here
          break if !key.empty? || (key.empty? && [':', '}'].include?(@scanner.peek(1)))
        end
        # --- End Key Parsing ---

        # Handle duplicate keys by rolling back and injecting a new object opening
        if @context.include?(:array) && object.key?(key)
          @scanner.pos = rollback_index - 1
          @scanner.string.insert(@scanner.pos + 1, '{')
          break # Exit the main object-parsing loop
        end

        skip_whitespaces
        next if @scanner.eos? || @scanner.peek(1) == '}' # End of object

        skip_whitespaces

        @scanner.scan(':') # Handle missing ':' after a key

        @context.pop
        @context.push(:object_value)

        skip_whitespaces

        value = ''
        # Handle stray comma or empty value before closing brace.
        value = parse_json unless [',', '}'].include?(@scanner.peek(1))

        @context.pop
        object[key] = value

        skip_whitespaces

        # Consume trailing comma or quotes.
        @scanner.scan(/[,'"]/)
        skip_whitespaces
      end

      return object unless @context.empty? # Don't do this in a nested context

      skip_whitespaces

      return object unless @scanner.scan(',')

      skip_whitespaces
      return object unless STRING_DELIMITERS.include?(@scanner.peek(1))

      # Recursively call parse_object to handle the extra pairs.
      # This relies on the parser's lenient behavior of not requiring a leading '{'.
      additional_obj = parse_object
      obj.merge!(additional_obj) if additional_obj.is_a?(Hash)

      object
    end

    # Parses a JSON array from the string.
    # Assumes the opening '[' has already been consumed by the caller.
    # This is a lenient parser designed to handle malformed JSON.
    def parse_array
      arr = []
      @context.push(:array)
      char = @scanner.peek(1)
      # Stop when you find the closing bracket or an invalid character like '}'
      while !@scanner.eos? && !["]", "}"].include?(char)
        skip_whitespaces

        value = ''
        if STRING_DELIMITERS.include?(char)
          # Sometimes it can happen that LLMs forget to start an object and then you think it's a string in an array
          # So we are going to check if this string is followed by a : or not
          # And either parse the string or parse the object
          i = 1
          i = skip_to_character(char, start_idx: i)
          i = skip_whitespaces_at(start_idx: i + 1)
          value = (@scanner.string[@scanner.pos + i] == ":" ? parse_object : parse_string)
        else
          value = parse_json
        end

        if is_strictly_empty(value)
          @scanner.pos += 1
        elsif value == "..." && @scanner.string[-1] == "."
        else
          arr << value
        end

        char = @scanner.peek(1)
        while char && char != "]" && (char.match?(/\s/) or char == ",")
          @scanner.pos += 1
          char = @scanner.peek(1)
        end
      end

      # Handle a potentially missing closing bracket, a common LLM error.
      @scanner.scan(']')
      @context.pop

      arr
    end

    # Parses a JSON string. This is a very lenient parser designed to handle
    # many common errors found in LLM-generated JSON, such as missing quotes,
    # incorrect escape sequences, and ambiguous string terminators
    def parse_string
      doubled_quotes = false
      missing_quotes = false
      lstring_delimiter = rstring_delimiter = '"'

      char = @scanner.peek(1)

      return parse_comment if ['#', '/'].include?(char)

      # A valid string can only start with a valid quote or, in our case, with a literal
      while char && !STRING_DELIMITERS.include?(char) && !char.match?(/[a-zA-Z0-9]/)
        @scanner.pos += 1
        char = @scanner.peek(1)
      end

      return '' if @scanner.eos?

      # --- Determine Delimiters and Handle Unquoted Literals ---
      case char
      when "'"
        lstring_delimiter = rstring_delimiter = "'"
      when '“'
        lstring_delimiter = '“'
        rstring_delimiter = '”'
      when /[a-zA-Z0-9]/
        # Could be a boolean/null, but not if it's an object key.
        if ["t", "f", "n"].include?(char.downcase) && current_context != :object_key
          # parse_literal is non-destructive if it fails to match.
          value = parse_literal
          return value if value != ''
        end
        # While parsing a string, we found a literal instead of a quote
        missing_quotes = true
      end

      @scanner.pos += 1 unless missing_quotes

      # There is sometimes a weird case of doubled quotes, we manage this also later in the while loop
      if STRING_DELIMITERS.include?(@scanner.peek(1)) && @scanner.peek(1) == lstring_delimiter
        next_value = @scanner.string[@scanner.pos + 1]

        if (
          current_context == :object_key && next_value == ':'
        ) || (
          current_context == :object_value && [",", "}"].include?(next_value)
        )
          @scanner.pos += 1
          return ''
        elsif next_value == lstring_delimiter
          # There's something fishy about this, we found doubled quotes and then again quotes
          return ''
        end

        i = skip_to_character(rstring_delimiter, start_idx: 1)
        next_c = @scanner.string[@scanner.pos + i]

        if next_c && @scanner.string[@scanner.pos + i + 1] == rstring_delimiter
          doubled_quotes = true
          @scanner.pos += 1
        else
          # Ok this is not a doubled quote, check if this is an empty string or not
          i = skip_whitespaces_at(start_idx: 1)
          next_c = @scanner.string[@scanner.pos + i]
          if [*STRING_DELIMITERS, '{', '['].include?(next_c)
            @scanner.pos += 1
            return ''
          elsif ![',', ']', '}'].include?(next_c)
            @scanner.pos += 1
          end
        end
      end

      string_acc = +''

      # Here things get a bit hairy because a string missing the final quote can also be a key or a value in an object
      # In that case we need to use the ":|,|}" characters as terminators of the string
      # So this will stop if:
      # * It finds a closing quote
      # * It iterated over the entire sequence
      # * If we are fixing missing quotes in an object, when it finds the special terminators
      char = @scanner.peek(1)
      unmatched_delimiter = false
      # --- Main Parsing Loop ---
      while !@scanner.eos? && char != rstring_delimiter
        if missing_quotes
          break if current_context == :object_key && (char == ':' || char.match?(/\s/))
          break if current_context == :array && [']', ','].include?(char)
          break if current_context == :object_value && [',', '}'].include?(char)
        end

        if char == ']' && @context.include?(:array) && string_acc[-1] != rstring_delimiter
          i = skip_to_character(rstring_delimiter)
          # No delimiter found
          break unless @scanner.string[@scanner.pos + i]
        end

        string_acc << char
        @scanner.pos += 1 # Consume the character
        char = @scanner.peek(1)
        if !@scanner.eos? && string_acc[-1] == "\\"
          # This is a special case, if people use real strings this might happen
          if [rstring_delimiter, 't', 'n', 'r', 'b', '\\'].include?(char)
            string_acc = string_acc.chop
            escape_seqs = { t: "\t", n: "\n", r: "\r", b: "\b" }
            string_acc << escape_seqs.fetch(char, char)
            @scanner.pos += 1 # Consume the character
            char = @scanner.peek(1)
            while char && string_acc[-1] == '\\' && [rstring_delimiter, '\\'].include?(char)
              # this is a bit of a special case, if I don't do this it will close the loop or create a train of \\
              # I don't love it though
              string_acc = string_acc.chop + char
              @scanner.pos += 1 # Consume the character
              char = @scanner.peek(1)
            end
            next
          elsif ['u', 'x'].include?(char)
            num_chars = (char == 'u' ? 4 : 2)
            next_chars = @scanner.peek(num_chars + 1)[1..]

            if next_chars.length == num_chars && next_chars.chars.all? { |c| '0123456789abcdefABCDEF'.include?(c) }
              string_acc = string_acc.chop + next_chars.to_i(16).chr('UTF-8')
              @scanner.pos += num_chars + 1
              char = @scanner.peek(1)
              next
            end
          elsif STRING_DELIMITERS.include?(char) && char != rstring_delimiter
            string_acc = string_acc.chop + char
            @scanner.pos += 1 # Consume the character
            char = @scanner.peek(1)
            next
          end
        end
        # If we are in object key context and we find a colon, it could be a missing right quote
        if (char == ':' && !missing_quotes && current_context == :object_key)
          i = skip_to_character(lstring_delimiter, start_idx: 1)
          next_c = @scanner.string[@scanner.pos + i]
          break unless next_c

          i += 1
          # found the first delimiter
          i = skip_to_character(rstring_delimiter, start_idx: i)
          next_c = @scanner.string[@scanner.pos + i]
          if next_c
            # found a second delimiter
            i += 1
            # Skip spaces
            i = skip_whitespaces_at(start_idx: i)
            next_c = @scanner.string[@scanner.pos + i]
            break if next_c && [',', '}'].include?(next_c)
          end

        end

        if (char == rstring_delimiter) && (string_acc[-1] != '\\')
          if doubled_quotes && @scanner.peek(1) == rstring_delimiter
            @scanner.pos += 1
          elsif missing_quotes && current_context == :object_value
            i = 1
            next_c = @scanner.string[@scanner.pos + i]
            while next_c && ![rstring_delimiter, lstring_delimiter].include?(next_c)
              i += 1
              next_c = @scanner.string[@scanner.pos + i]
            end
            if next_c
              # We found a quote, now let's make sure there's a ":" following
              i += 1
              # found a delimiter, now we need to check that is followed strictly by a comma or brace
              i = skip_whitespaces_at(start_idx: i)
              next_c = @scanner.string[@scanner.pos + i]
              if next_c && next_c == ':'
                @scanner.pos -= 1
                char = @scanner.peek(1)
                break
              end
            end
          elsif unmatched_delimiter
            unmatched_delimiter = false
            string_acc << char.to_s
            @scanner.pos += 1 # Consume the character
            char = @scanner.peek(1)
          else
            # Check if eventually there is a rstring delimiter, otherwise we bail
            i = 1
            next_c = @scanner.string[@scanner.pos + i]
            check_comma_in_object_value = true
            while next_c && ![rstring_delimiter, lstring_delimiter].include?(next_c)
              # This is a bit of a weird workaround, essentially in object_value context we don't always break on commas
              # This is because the routine after will make sure to correct any bad guess and this solves a corner case
              check_comma_in_object_value = false if check_comma_in_object_value && next_c.match?(/[a-zA-Z]/)
              # If we are in an object context, let's check for the right delimiters
              if (@context.include?(:object_key) && [':', '}'].include?(next_c)) ||
                (@context.include?(:object_value) && next_c == '}') ||
                (@context.include?(:array) && [']', ','].include?(next_c)) ||
                (
                  check_comma_in_object_value &&
                  current_context == :object_value &&
                  next_c == ','
                )
                break
              end

              i += 1
              next_c = @scanner.string[@scanner.pos + i]
            end

            # If we stopped for a comma in object_value context, let's check if find a "} at the end of the string
            if next_c == ',' && current_context == :object_value
              i += 1
              i = skip_to_character(rstring_delimiter, start_idx: i)
              next_c = @scanner.string[@scanner.pos + i]
              # Ok now I found a delimiter, let's skip whitespaces and see if next we find a } or a ,
              i += 1
              i = skip_whitespaces_at(start_idx: i)
              next_c = @scanner.string[@scanner.pos + i]
              if ['}', ','].include?(next_c)
                string_acc << char.to_s
                @scanner.pos += 1 # Consume the character
                char = @scanner.peek(1)
                next
              end
            elsif next_c == rstring_delimiter && @scanner.string[@scanner.pos + i - 1] != '\\'
              # Check if self.index:self.index+i is only whitespaces, break if that's the case
              break if (1..i).all? { |j| @scanner.string[@scanner.pos + j].to_s.match(/\s/) }

              if current_context == :object_value
                i = skip_whitespaces_at(start_idx: i + 1)
                if @scanner.string[@scanner.pos + i] == ','
                  # So we found a comma, this could be a case of a single quote like "va"lue",
                  # Search if it's followed by another key, starting with the first delimeter
                  i = skip_to_character(lstring_delimiter, start_idx: i + 1)
                  i += 1
                  i = skip_to_character(rstring_delimiter, start_idx: i + 1)
                  i += 1
                  i = skip_whitespaces_at(start_idx: i)
                  next_c = @scanner.string[@scanner.pos + i]
                  if next_c == ':'
                    string_acc << char.to_s
                    @scanner.pos += 1 # Consume the character
                    char = @scanner.peek(1)
                    next
                  end
                end
                # We found a delimiter and we need to check if this is a key
                # so find a rstring_delimiter and a colon after
                i = skip_to_character(rstring_delimiter, start_idx: i + 1)
                i += 1
                next_c = @scanner.string[@scanner.pos + i]
                while next_c && next_c != ':'
                  if [',', ']', '}'].include?(next_c) || (
                    next_c == rstring_delimiter &&
                    @scanner.string[@scanner.pos + i - 1] != '\\'
                  )
                    break
                  end

                  i += 1
                  next_c = @scanner.string[@scanner.pos + i]
                end

                # Only if we fail to find a ':' then we know this is misplaced quote
                if next_c != ':'
                  unmatched_delimiter = !unmatched_delimiter
                  string_acc << char.to_s
                  @scanner.pos += 1 # Consume the character
                  char = @scanner.peek(1)
                end
              elsif current_context == :array
                # So here we can have a few valid cases:
                # ["bla bla bla "puppy" bla bla bla "kitty" bla bla"]
                # ["value1" value2", "value3"]
                # The basic idea is that if we find an even number of delimiters after this delimiter
                # we ignore this delimiter as it should be fine
                even_delimiters = next_c == rstring_delimiter
                while next_c == rstring_delimiter
                  i = skip_to_character([rstring_delimiter, ']'], start_idx: i + 1)
                  next_c = @scanner.string[@scanner.pos + i]
                  if next_c != rstring_delimiter
                    even_delimiters = false
                    break
                  end
                  i = skip_to_character([rstring_delimiter, ']'], start_idx: i + 1)
                  next_c = @scanner.string[@scanner.pos + i]
                end

                break unless even_delimiters

                unmatched_delimiter = !unmatched_delimiter
                string_acc << char.to_s
                @scanner.pos += 1 # Consume the character
                char = @scanner.peek(1)
              elsif current_context == :object_key
                string_acc << char.to_s
                @scanner.pos += 1 # Consume the character
                char = @scanner.peek(1)
              end
            end
          end

        end
      end

      if !@scanner.eos? && missing_quotes && current_context == :object_key && char.match(/\s/)
        skip_whitespaces
        return '' unless [':', ','].include?(@scanner.peek(1))
      end

      # A fallout of the previous special case in the while loop,
      # we need to update the index only if we had a closing quote
      if char == rstring_delimiter
        @scanner.pos += 1
      else
        string_acc.rstrip!
      end

      string_acc.rstrip! if missing_quotes || (string_acc && string_acc[-1] == "\n")

      string_acc
    end

    # Parses a JSON number, which can be an integer or a floating-point value.
    # This parser is lenient and will also handle currency-like strings with commas,
    # returning them as a string. It attempts to handle various malformed number
    # inputs that might be generated by LLMs
    def parse_number
      # The set of valid characters for a number depends on the context.
      # Inside an array, a comma terminates the number.
      number_str = +''
      char = @scanner.peek(1)

      while char && NUMBER_CHARS.include?(char) && (
        !(current_context == :array) || char != ","
      )
        number_str << char
        @scanner.pos += 1 # Consume the character
        char = @scanner.peek(1) # Peek at the next character for the next iteration
      end

      # Handle cases where the number ends with an invalid character.
      if number_str && /[-eE,]\z/.match?(number_str)
        number_str.chop!
        @scanner.pos -= 1
      # Handle cases where what looked like a number is actually a string.
      # e.g., "123-abc"
      elsif @scanner.peek(1)&.match?(/[a-zA-Z]/)
        # Roll back the entire scan and re-parse as a string.
        @scanner.pos -= number_str.length
        return parse_string
      end

      # Attempt to convert the string to the appropriate number type.
      # Use rescue to handle conversion errors gracefully, returning the original string.
      begin
        if number_str.include?(',')
          return number_str.to_s
        elsif number_str.match?(/[\.eE]/)
          Float(number_str)
        else
          Integer(number_str)
        end
      rescue ArgumentError
        number_str
      end
    end

    # Parses the JSON literals `true`, `false`, or `null`.
    # This is case-insensitive.
    def parse_literal
      if @scanner.scan(/true/i)
        return true
      elsif @scanner.scan(/false/i)
        return false
      elsif @scanner.scan(/null/i)
        return nil
      end

      # If nothing matches, return an empty string to signify that this
      # was not a boolean or null value, consistent with the Python version.
      ''
    end

    # Parses and skips over code-style comments.
    # - # line comment
    # - // line comment
    # - /* block comment */
    # After skipping the comment, it either continues parsing if at the top level
    # or returns an empty string to be ignored by the caller.
    def parse_comment
      # Determine valid line comment termination characters based on the current context.
      termination_chars = ["\n", "\r"]
      termination_chars << ']' if @context.include?(:array)
      termination_chars << '}' if @context.include?(:object_value)
      termination_chars << ':' if @context.include?(:object_key)
      line_comment_matcher = Regexp.new("[#{Regexp.escape(termination_chars.join)}]")

      # Line comment starting with #
      if @scanner.skip(/#/)
        # Skip until the next terminator or the end of the string.
        found_terminator = @scanner.skip_until(line_comment_matcher)
        @scanner.terminate unless found_terminator
      # Comments starting with /
      elsif @scanner.check(%r{/})
        # Handle line comment starting with //
        if @scanner.skip(%r{//})
          found_terminator = @scanner.skip_until(line_comment_matcher)
          @scanner.terminate unless found_terminator

        # Handle block comment starting with /*
        elsif @scanner.skip(%r{/\*})
          found_terminator = @scanner.skip_until(%r{\*/})
          @scanner.terminate unless found_terminator

        # Handle standalone '/' characters that are not part of a comment.
        else
          @scanner.pos += 1 # Skip it to avoid an infinite loop.
        end
      end

      # If we've parsed a top-level comment, continue parsing the next JSON element.
      # Otherwise, return an empty string to signify the comment was ignored.
      return parse_json if @context.empty?

      ''
    end

    # This function is a non-destructive lookahead.
    # It quickly iterates to find a character, handling escaped characters, and
    # returns the index (offset) from the scanner
    def skip_to_character(characters, start_idx: 0)
      # Get the rest of the string from the scanner's current position for lookahead.
      search_string = @scanner.rest
      character_list = Array(characters)
      current_idx = start_idx

      while current_idx < search_string.length
        # If the character at the current index is one we're looking for...
        if character_list.include?(search_string[current_idx])
          # ...check if it's escaped by a preceding backslash.
          return current_idx unless current_idx.positive? && search_string[current_idx - 1] == '\\'

          # It was escaped, so we continue our search from the next character.
          current_idx += 1
          next

          # It's not escaped. We've found our character. Return its index.

        end
        current_idx += 1
      end

      # If the loop completes, the character was not found. Return the final index,
      # which points to the end of the search string.
      current_idx
    end

    # This function uses the StringScanner to skip whitespace from the current position.
    # It is more efficient and idiomatic than manual index management
    def skip_whitespaces_at(start_idx: 0)
      idx = start_idx
      # This function quickly iterates on whitespaces, syntactic sugar to make the code more concise
      char = @scanner.string[@scanner.pos + idx]
      return idx if char.nil?

      while char && char.match?(/\s/)
        idx += 1
        char = @scanner.string[@scanner.pos + idx]
      end

      idx
    end

    # Helper to check if two objects are of the same container type (Array or Hash).
    def same_object_type?(obj1, obj2)
      (obj1.is_a?(Array) && obj2.is_a?(Array)) || (obj1.is_a?(Hash) && obj2.is_a?(Hash))
    end

    def is_strictly_empty(value)
      # Check if the value is a container AND if it's empty.
      [String, Array, Hash, Set].any? { |klass| value.is_a?(klass) } && value.empty?
    end

    # Skips whitespaces
    def skip_whitespaces
      @scanner.skip(/\s+/)
    end

    def current_context
      @context&.last
    end
  end
end
