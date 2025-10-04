# frozen_string_literal: true

require 'strscan'
require 'set'

# Root module
module JsonMend
  # The core parser that does the heavy lifting of fixing the JSON.
  class Parser
    COMMENT_DELIMETERS = ['#', '/'].freeze
    NUMBER_CHARS = Set.new('0123456789-.eE/,'.chars).freeze
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
        until @scanner.eos?
          new_json = parse_json
          if new_json.empty?
            @scanner.getch # continue
          else
            json.pop if same_object_type?(json.last, new_json)
            json << new_json
          end
        end

        json = json.first if json.length > 1
      end

      json
    end

    private

    def parse_json
      until @scanner.eos?
        case peek_char
        when '{'
          @scanner.getch # consume '{'
          return parse_object
        when '['
          @scanner.getch # consume '['
          return parse_array
        when ->(c) { STRING_DELIMITERS.include?(c) || c&.match?(/\p{L}/) }
          return parse_string
        when ->(c) { c&.match?(/\d/) || c == '-' || c == '.' }
          return parse_number
        when *COMMENT_DELIMETERS
          return parse_comment
        else
          @scanner.getch # moving by string, ignore this symbol
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
        rollback_index = @scanner.charpos

        # --- Key Parsing ---
        key = ''
        while !@scanner.eos?
          rollback_index = @scanner.charpos # Update rollback position
          # Is this an array?
          # Need to check if the previous parsed value contained in obj is an array and in that case parse and merge the two
          if key.empty? && peek_char == '['
            prev_key = object.keys.last
            if prev_key && object[prev_key].is_a?(Array)
              @scanner.getch # consume '['
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
          break if !key.empty? || (key.empty? && [':', '}'].include?(peek_char))
        end
        # --- End Key Parsing ---

        # Handle duplicate keys by rolling back and injecting a new object opening
        if context_contain?(:array) && object.key?(key)
          # Convert the character-based rollback_index to a byte-based index for string manipulation.
          # We do this by taking the substring up to the character position and getting its byte length.
          byte_rollback_index = @scanner.string.chars[0...rollback_index].join.bytesize

          # Now, use the byte-based index for all string slicing and scanner positioning.
          @scanner = StringScanner.new([
            @scanner.string.byteslice(0...byte_rollback_index),
            '{',
            @scanner.string.byteslice(byte_rollback_index..-1)
          ].join)

          # Set the scanner's position to the new byte index.
          @scanner.pos = byte_rollback_index
          break # Exit the main object-parsing loop
        end

        skip_whitespaces
        next if @scanner.eos? || peek_char == '}' # End of object

        skip_whitespaces

        @scanner.scan(':') # Handle missing ':' after a key

        @context.pop
        @context.push(:object_value)

        skip_whitespaces

        value = ''
        # Handle stray comma or empty value before closing brace.
        value = parse_json unless [',', '}'].include?(peek_char)

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
      return object unless STRING_DELIMITERS.include?(peek_char)

      # Recursively call parse_object to handle the extra pairs.
      # This relies on the parser's lenient behavior of not requiring a leading '{'.
      additional_obj = parse_object
      object.merge!(additional_obj) if additional_obj.is_a?(Hash)

      object
    end

    # Parses a JSON array from the string.
    # Assumes the opening '[' has already been consumed by the caller.
    # This is a lenient parser designed to handle malformed JSON.
    def parse_array
      arr = []
      @context.push(:array)
      char = peek_char
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
          value = (peek_char(i) == ":" ? parse_object : parse_string)
        else
          value = parse_json
        end

        if is_strictly_empty(value)
          @scanner.getch
        elsif value == "..." && @scanner.string.chars[@scanner.charpos - 1] == '.'
        else
          arr << value
        end

        char = peek_char
        while char && char != "]" && (char.match?(/\s/) or char == ",")
          @scanner.getch
          char = peek_char
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

      char = peek_char

      return parse_comment if ['#', '/'].include?(char)

      # A valid string can only start with a valid quote or, in our case, with a literal
      while !@scanner.eos? && !STRING_DELIMITERS.include?(char) && !char.match?(/[\p{L}0-9]/)
        @scanner.getch
        char = peek_char
      end

      return '' if @scanner.eos?

      # --- Determine Delimiters and Handle Unquoted Literals ---
      case char
      when "'"
        lstring_delimiter = rstring_delimiter = "'"
      when '“'
        lstring_delimiter = '“'
        rstring_delimiter = '”'
      when /[\p{L}0-9]/
        # Could be a boolean/null, but not if it's an object key.
        if ["t", "f", "n"].include?(char.downcase) && current_context != :object_key
          # parse_literal is non-destructive if it fails to match.
          value = parse_literal
          return value if value != ''
        end
        # While parsing a string, we found a literal instead of a quote
        missing_quotes = true
      end

      @scanner.getch unless missing_quotes

      # There is sometimes a weird case of doubled quotes, we manage this also later in the while loop
      if STRING_DELIMITERS.include?(peek_char) && peek_char == lstring_delimiter
        next_value = peek_char(1)

        if (
          current_context == :object_key && next_value == ':'
        ) || (
          current_context == :object_value && [",", "}"].include?(next_value)
        )
          @scanner.getch
          return ''
        elsif next_value == lstring_delimiter
          # There's something fishy about this, we found doubled quotes and then again quotes
          return ''
        end

        i = skip_to_character(rstring_delimiter, start_idx: 1)
        next_c = peek_char(i)

        if next_c && peek_char(i + 1) == rstring_delimiter
          doubled_quotes = true
          @scanner.getch
        else
          # Ok this is not a doubled quote, check if this is an empty string or not
          i = skip_whitespaces_at(start_idx: 1)
          next_c = peek_char(i)
          if [*STRING_DELIMITERS, '{', '['].include?(next_c)
            @scanner.getch
            return ''
          elsif ![',', ']', '}'].include?(next_c)
            @scanner.getch
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
      char = peek_char
      unmatched_delimiter = false
      # --- Main Parsing Loop ---
      while !@scanner.eos? && char != rstring_delimiter
        if missing_quotes
          break if current_context == :object_key && (char == ':' || char.match?(/\s/))
          break if current_context == :array && [']', ','].include?(char)
        end

        if current_context == :object_value && [',', '}'].include?(char) && (string_acc.empty? || string_acc[-1] != rstring_delimiter)
          rstring_delimiter_missing = true
          # check if this is a case in which the closing comma is NOT missing instead
          skip_whitespaces
          if peek_char(1) == '\\'
            # Ok this is a quoted string, skip
            rstring_delimiter_missing = true
            i = skip_to_character(rstring_delimiter, start_idx: 1)
            next_c = peek_char(i)
            if next_c
              i += 1
              # found a delimiter, now we need to check that is followed strictly by a comma or brace
              # or the string ended
              i = skip_whitespaces_at(start_idx: i)
              next_c = peek_char(i)
              if next_c.nil? || [',', '}'].include?(next_c)
                rstring_delimiter_missing = false
              else
                # OK but this could still be some garbage at the end of the string
                # So we need to check if we find a new lstring_delimiter afterwards
                # If we do, maybe this is a missing delimiter
                i = skip_to_character(lstring_delimiter, start_idx: i)
                next_c = peek_char(i)
                if next_c.nil?
                  rstring_delimiter_missing = false
                else
                  # But again, this could just be something a bit stupid like "lorem, "ipsum" sic"
                  # Check if we find a : afterwards (skipping space)
                  i = skip_whitespaces_at(start_idx: i + 1)
                  next_c = peek_char(i)
                  if next_c && next_c != ":"
                    rstring_delimiter_missing = false
                  end
                end
              end
            else
              # There could be a case in which even the next key:value is missing delimeters
              # because it might be a systemic issue with the output
              # So let's check if we can find a : in the string instead
              i = skip_to_character(':', start_idx: 1)
              next_c = peek_char(i)
              if next_c
                # OK then this is a systemic issue with the output
                break
              else
                # skip any whitespace first
                i = skip_whitespaces_at(start_idx: 1)
                # We couldn't find any rstring_delimeter before the end of the string
                # check if this is the last string of an object and therefore we can keep going
                # make an exception if this is the last char before the closing brace
                j = skip_to_character('}', start_idx: i)
                if j - i > 1
                  # Ok it's not right after the comma
                  # Let's ignore
                  rstring_delimiter_missing = false
                elsif peek_char(j)
                  # Check for an unmatched opening brace in string_acc
                  string_acc.reverse.chars.each do |c|
                    if c == '{'
                      # Ok then this is part of the string
                      rstring_delimiter_missing = false
                      break
                    end
                  end
                end
              end
            end

            if rstring_delimiter_missing
              break
            end
          end
        end

        if char == ']' && context_contain?(:array) && string_acc[-1] != rstring_delimiter
          i = skip_to_character(rstring_delimiter)
          # No delimiter found
          break unless peek_char(i)
        end

        string_acc << char
        @scanner.getch # Consume the character
        char = peek_char

        if !@scanner.eos? && string_acc[-1] == "\\"
          # This is a special case, if people use real strings this might happen
          if [rstring_delimiter, 't', 'n', 'r', 'b', '\\'].include?(char)
            string_acc = string_acc.chop
            escape_seqs = { 't' => "\t", 'n' => "\n", 'r' => "\r", 'b' => "\b" }
            string_acc << escape_seqs.fetch(char, char)
            @scanner.getch # Consume the character
            char = peek_char
            while !@scanner.eos? && string_acc[-1] == '\\' && [rstring_delimiter, '\\'].include?(char)
              # this is a bit of a special case, if I don't do this it will close the loop or create a train of \\
              # I don't love it though
              string_acc = string_acc.chop + char
              @scanner.getch # Consume the character
              char = peek_char
            end
            next
          elsif ['u', 'x'].include?(char)
            num_chars = (char == 'u' ? 4 : 2)
            next_chars = @scanner.peek(num_chars + 1)[1..]

            if next_chars.length == num_chars && next_chars.chars.all? { |c| '0123456789abcdefABCDEF'.include?(c) }
              string_acc = string_acc.chop + next_chars.to_i(16).chr('UTF-8')
              @scanner.pos += num_chars + 1
              char = peek_char
              next
            end
          elsif STRING_DELIMITERS.include?(char) && char != rstring_delimiter
            string_acc = string_acc.chop + char
            @scanner.getch # Consume the character
            char = peek_char
            next
          end
        end
        # If we are in object key context and we find a colon, it could be a missing right quote
        if (char == ':' && !missing_quotes && current_context == :object_key)
          i = skip_to_character(lstring_delimiter, start_idx: 1)
          next_c = peek_char(i)
          break unless next_c

          i += 1
          # found the first delimiter
          i = skip_to_character(rstring_delimiter, start_idx: i)
          next_c = peek_char(i)
          if next_c
            # found a second delimiter
            i += 1
            # Skip spaces
            i = skip_whitespaces_at(start_idx: i)
            next_c = peek_char(i)
            break if next_c && [',', '}'].include?(next_c)
          end

        end

        if char == rstring_delimiter && string_acc[-1] != '\\'
          if doubled_quotes && peek_char(1) == rstring_delimiter
            @scanner.getch
          elsif missing_quotes && current_context == :object_value
            i = 1
            next_c = peek_char(i)
            while next_c && ![rstring_delimiter, lstring_delimiter].include?(next_c)
              i += 1
              next_c = peek_char(i)
            end
            if next_c
              # We found a quote, now let's make sure there's a ":" following
              i += 1
              # found a delimiter, now we need to check that is followed strictly by a comma or brace
              i = skip_whitespaces_at(start_idx: i)
              next_c = peek_char(i)
              if next_c && next_c == ':'
                @scanner.pos -= 1
                char = peek_char
                break
              end
            end
          elsif unmatched_delimiter
            unmatched_delimiter = false
            string_acc << char.to_s
            @scanner.getch # Consume the character
            char = peek_char
          else
            # Check if eventually there is a rstring delimiter, otherwise we bail
            i = 1
            next_c = peek_char(i)
            check_comma_in_object_value = true
            while next_c && ![rstring_delimiter, lstring_delimiter].include?(next_c)
              # This is a bit of a weird workaround, essentially in object_value context we don't always break on commas
              # This is because the routine after will make sure to correct any bad guess and this solves a corner case
              check_comma_in_object_value = false if check_comma_in_object_value && next_c.match?(/\p{L}/)
              # If we are in an object context, let's check for the right delimiters
              if (context_contain?(:object_key) && [':', '}'].include?(next_c)) ||
                (context_contain?(:object_value) && next_c == '}') ||
                (context_contain?(:array) && [']', ','].include?(next_c)) ||
                (
                  check_comma_in_object_value &&
                  current_context == :object_value &&
                  next_c == ','
                )
                break
              end

              i += 1
              next_c = peek_char(i)
            end

            # If we stopped for a comma in object_value context, let's check if find a "} at the end of the string
            if next_c == ',' && current_context == :object_value
              i += 1
              i = skip_to_character(rstring_delimiter, start_idx: i)
              next_c = peek_char(i)
              # Ok now I found a delimiter, let's skip whitespaces and see if next we find a } or a ,
              i += 1
              i = skip_whitespaces_at(start_idx: i)
              next_c = peek_char(i)
              if ['}', ','].include?(next_c)
                string_acc << char.to_s
                @scanner.getch # Consume the character
                char = peek_char
                next
              end
            elsif next_c == rstring_delimiter && peek_char(i - 1) != '\\'
              # Check if self.index:self.index+i is only whitespaces, break if that's the case
              break if (1..i).all? { |j| peek_char(j).to_s.match(/\s/) }

              if current_context == :object_value
                i = skip_whitespaces_at(start_idx: i + 1)
                if peek_char(i) == ','
                  # So we found a comma, this could be a case of a single quote like "va"lue",
                  # Search if it's followed by another key, starting with the first delimeter
                  i = skip_to_character(lstring_delimiter, start_idx: i + 1)
                  i += 1
                  i = skip_to_character(rstring_delimiter, start_idx: i + 1)
                  i += 1
                  i = skip_whitespaces_at(start_idx: i)
                  next_c = peek_char(i)
                  if next_c == ':'
                    string_acc << char.to_s
                    @scanner.getch # Consume the character
                    char = peek_char
                    next
                  end
                end
                # We found a delimiter and we need to check if this is a key
                # so find a rstring_delimiter and a colon after
                i = skip_to_character(rstring_delimiter, start_idx: i + 1)
                i += 1
                next_c = peek_char(i)
                while next_c && next_c != ':'
                  if [',', ']', '}'].include?(next_c) || (
                    next_c == rstring_delimiter &&
                    peek_char(i - 1) != '\\'
                  )
                    break
                  end

                  i += 1
                  next_c = peek_char(i)
                end

                # Only if we fail to find a ':' then we know this is misplaced quote
                if next_c != ':'
                  unmatched_delimiter = !unmatched_delimiter
                  string_acc << char.to_s
                  @scanner.getch # Consume the character
                  char = peek_char
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
                  next_c = peek_char(i)
                  if next_c != rstring_delimiter
                    even_delimiters = false
                    break
                  end
                  i = skip_to_character([rstring_delimiter, ']'], start_idx: i + 1)
                  next_c = peek_char(i)
                end

                break unless even_delimiters

                unmatched_delimiter = !unmatched_delimiter
                string_acc << char.to_s
                @scanner.getch # Consume the character
                char = peek_char
              elsif current_context == :object_key
                string_acc << char.to_s
                @scanner.getch # Consume the character
                char = peek_char
              end
            end
          end

        end
      end

      if !@scanner.eos? && missing_quotes && current_context == :object_key && char.match(/\s/)
        skip_whitespaces
        return '' unless [':', ','].include?(peek_char)
      end

      # A fallout of the previous special case in the while loop,
      # we need to update the index only if we had a closing quote
      if char == rstring_delimiter
        @scanner.getch
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
      allowed_chars = NUMBER_CHARS.dup
      allowed_chars.delete(',') if current_context == :array
      regex = /[#{Regexp.escape(allowed_chars.to_a.join)}]+/

      scanned_str = @scanner.scan(regex)
      return nil unless scanned_str

      # Handle cases where the number ends with an invalid character.
      if !scanned_str.empty? && ['-', 'e', 'E', ','].include?(scanned_str[-1])
        @scanner.pos -= scanned_str[-1].bytesize
        scanned_str.chop!
      # Handle cases where what looked like a number is actually a string.
      # e.g., "123-abc"
      elsif peek_char&.match?(/\p{L}/)
        # Roll back the entire scan and re-parse as a string.
        @scanner.pos -= scanned_str.bytesize
        return parse_string
      end

      # Attempt to convert the string to the appropriate number type.
      # Use rescue to handle conversion errors gracefully, returning the original string.
      begin
        if scanned_str.include?(',')
          return scanned_str.to_s
        elsif scanned_str.match?(/[\.eE]/)
          Float(scanned_str)
        else
          Integer(scanned_str)
        end
      rescue ArgumentError
        scanned_str
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
      # was not a boolean or null value
      ''
    end

    # Parses and skips over code-style comments.
    # - # line comment
    # - // line comment
    # - /* block comment */
    # After skipping the comment, it either continues parsing if at the top level
    # or returns an empty string to be ignored by the caller.
    def parse_comment
      # Check for a block comment `/* ... */`
      if @scanner.scan(%r{/\*})
        # Scan until the closing delimiter is found.
        # The `lazy` quantifier `*?` ensures we stop at the *first* `*/`.
        @scanner.scan_until(%r{\*/})

      # Check for a line comment `//...` or `#...`
      elsif @scanner.scan(%r{//|#})
        # Determine valid line comment termination characters based on context.
        termination_chars = ["\n", "\r"]
        termination_chars << ']' if context_contain?(:array)
        termination_chars << '}' if context_contain?(:object_value)
        termination_chars << ':' if context_contain?(:object_key)

        # Create a regex that will scan until it hits one of the terminators.
        # The terminators are positive lookaheads, so they aren't consumed by the scan.
        terminator_regex = Regexp.new("(?=#{termination_chars.map { |c| Regexp.escape(c) }.join('|')})")

        # Scan until the end of the comment.
        @scanner.scan_until(terminator_regex)
      else
        # The character at the current position (likely '/') is not the start of a
        # valid comment. To prevent an infinite loop in the calling parser, we must
        # consume this single stray character before exiting.
        @scanner.getch
      end

      skip_whitespaces

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

      # byte_pos will track our position in bytes.
      byte_pos = 0

      # We iterate through each character, getting the character itself and its character index.
      # The .chars method is UTF-8 aware.
      search_string.chars.each_with_index do |char, char_index|

        # Only start checking for matches once we are past the start_idx (in bytes).
        if byte_pos >= start_idx && character_list.include?(char)

          # Check if the character is escaped.
          is_escaped = false
          if char_index > 0

            # Look backwards from the character before the current one.
            temp_index = char_index - 1
            slash_count = 0

            # Count how many consecutive backslashes precede the character.
            while temp_index >= 0 && search_string[temp_index] == '\\'
              slash_count += 1
              temp_index -= 1
            end

            # An odd number of backslashes means the character is escaped.
            is_escaped = slash_count.odd?
          end

          # If it's not escaped, we've found our match. Return the byte position.
          return byte_pos unless is_escaped
        end

        # Advance the byte position by the byte size of the current character.
        byte_pos += char.bytesize
      end

      # If the loop completes, the character was not found. Return the total byte length.
      search_string.bytesize
    end

    # This function uses the StringScanner to skip whitespace from the current position.
    # It is more efficient and idiomatic than manual index management
    def skip_whitespaces_at(start_idx: 0)
      idx = start_idx
      # This function quickly iterates on whitespaces, syntactic sugar to make the code more concise
      char = peek_char(idx)
      return idx if char.nil?

      while !@scanner.eos? && char.match?(/\s/)
        idx += 1
        char = peek_char(idx)
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

    def peek_char(offset = 0)
      # Peeks the next character without advancing the scanner
      rest_of_string = @scanner.rest
      rest_of_string.chars[offset]
    end

    def current_context
      @context&.last
    end

    def context_contain?(value)
      @context.include?(value)
    end
  end
end
