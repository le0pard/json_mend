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
    ESCAPE_MAPPING = {
      't' => "\t",
      'n' => "\n",
      'r' => "\r",
      'b' => "\b"
    }.freeze
    JSON_STOP_TOKEN = :json_mend_stop_token

    # Pre-compile regexes for performance
    NUMBER_REGEX = /[#{Regexp.escape(NUMBER_CHARS.to_a.join)}]+/
    NUMBER_NO_COMMA_REGEX = /[#{Regexp.escape(NUMBER_CHARS.dup.tap { |s| s.delete(',') }.to_a.join)}]+/

    def initialize(json_string)
      @scanner = StringScanner.new(json_string)
      @context = []
    end

    # Kicks off the parsing process. This is a direct port of the robust Python logic.
    def parse
      json = parse_json

      # If the first parse returns JSON_STOP_TOKEN, it means we found nothing (empty string or garbage).
      # Return nil (or empty string representation logic elsewhere handles it).
      return nil if json == JSON_STOP_TOKEN

      unless @scanner.eos?
        json = [json]
        until @scanner.eos?
          new_json = parse_json
          if new_json == ''
            @scanner.getch # continue
          elsif new_json == JSON_STOP_TOKEN
            # Found nothing but EOS or garbage terminator
            break
          else
            # Ignore strings that look like closing braces garbage (e.g. "}", " ] ")
            next if new_json.is_a?(String) && new_json.strip.match?(/^[}\]]+$/)

            json.pop if same_object_type?(json.last, new_json)
            json << new_json
          end
        end

        json = json.first if json.length == 1
      end

      json
    end

    private

    def parse_json
      until @scanner.eos?
        char = peek_char
        case char
        when '{'
          @scanner.getch # consume '{'
          return parse_object
        when '['
          @scanner.getch # consume '['
          return parse_array
        when *COMMENT_DELIMETERS
          # Avoid recursion: consume comment and continue loop
          parse_comment
        else
          if string_start?(char)
            if @context.empty? && !STRING_DELIMITERS.include?(char)
              # Top level unquoted string strictness:
              # Only allow literals (true/false/null), ignore other text as garbage.
              val = parse_literal
              return val if val != ''

              @scanner.getch
              next
            end
            return parse_string
          elsif number_start?(char)
            val = parse_number
            return val unless val == ''

            @scanner.getch
          else
            # Stop if we hit a terminator for the current context to avoid consuming it as garbage
            if (current_context?(:array) && char == ']') ||
               (current_context?(:object_value) && char == '}') ||
               (current_context?(:object_key) && char == '}')
              return JSON_STOP_TOKEN
            end

            @scanner.getch # moving by string, ignore this symbol
          end
        end
      end
      JSON_STOP_TOKEN
    end

    # Parses a JSON object.
    def parse_object
      object = {}

      loop do
        skip_whitespaces

        # >> PRIMARY EXIT: End of object or end of string.
        break if @scanner.eos? || @scanner.scan('}') || peek_char == ']'

        # Leniently consume any leading junk characters (like stray commas or colons)
        # that might appear before a key.
        @scanner.skip(/[,\s:]+/)

        # --- Delegate to a helper to parse the next Key-Value pair ---
        key, value, colon_found = parse_object_pair(object)
        next if %i[merged_array stray_colon].include?(key)

        # If the helper returns nil for the key, it signals that we should
        # stop parsing this object (e.g., a duplicate key was found,
        # indicating the start of a new object).
        if key.nil?
          @scanner.scan('}')
          break
        end

        # Assign the parsed pair to our object, avoiding empty keys.
        # But only if we didn't firmly establish the key with a colon already.
        skip_whitespaces
        if peek_char == ':' && !colon_found
          key = value.to_s
          @scanner.getch # consume ':'
          value = parse_object_value
        end

        # Assign the parsed pair to our object.
        object[key] = value
      end

      object
    end

    # Attempts to parse a single key-value pair.
    # Returns [key, value] on success, or [nil, nil] if parsing should stop.
    def parse_object_pair(object)
      # --- 1. Parse the Key ---
      # This step includes the complex logic for merging dangling arrays.
      pos_before_key = @scanner.pos
      key, was_array_merged, is_bracketed = parse_object_key(object)

      # If an array was merged, there's no K/V pair to process, so we restart the loop.
      return [:merged_array, nil, false] if was_array_merged

      # Check for a stray colon: invalid structure where we have no key (and no quotes consumed) but see a colon.
      # This handles cases like: { "key": "value", : "garbage" }
      if key.empty? && (@scanner.pos == pos_before_key) && peek_char == ':'
        @scanner.getch # Skip ':'
        parse_object_value # Consume and discard the value
        return [:stray_colon, nil, false]
      end

      # If we get an empty key and the next character is a closing brace, we're done.
      return [nil, nil, false] if key.empty? && (peek_char.nil? || peek_char == '}')

      # --- 2. Handle Duplicate Keys (Safer Method) ---
      # This is a critical repair for lists of objects missing a comma separator.
      if object.key?(key)
        # Instead of rewriting the string, we safely rewind the scanner to the
        # position before the duplicate key. This ends the parsing of the current
        # object, allowing the top-level parser to see the duplicate key as the
        # start of a new JSON object.
        @scanner.pos = pos_before_key
        return [nil, nil, false] # Signal to stop parsing this object.
      end

      # --- 3. Parse the Separator (:) ---
      skip_whitespaces
      colon_found = @scanner.skip(/:/) # Leniently skip the colon if it exists.

      # --- 4. Parse the Value ---
      value = parse_object_value(colon_found: colon_found || is_bracketed)

      if value == :inferred_true
        return [nil, nil, false] if %w[true false null].include?(key.downcase)

        value = true
      end

      [key, value, colon_found]
    end

    # Parses the key of an object, including the special logic for merging dangling arrays.
    # Returns [key, was_array_merged_flag]
    def parse_object_key(object)
      # First, check for and handle the dangling array merge logic.
      if try_to_merge_dangling_array(object)
        return [nil, true, false] # Signal that an array was merged.
      end

      # If no merge happened, proceed with standard key parsing.
      @context.push(:object_key)
      is_bracketed = false

      if peek_char == '['
        @scanner.getch # Consume '['
        arr = parse_array
        key = arr.first.to_s
        is_bracketed = true
      else
        key = parse_string.to_s
      end
      @context.pop

      # If the key is empty, consume any stray characters to prevent infinite loops.
      @scanner.getch if key.empty? && !@scanner.check(/[:}]/) && !@scanner.eos?

      [key, false, is_bracketed] # Signal that a key was parsed.
    end

    # Parses the value part of a key-value pair.
    def parse_object_value(colon_found: true)
      @context.push(:object_value)
      skip_whitespaces

      # Handle cases where the value is missing (e.g., "key": } or "key": ,)
      if @scanner.eos? || @scanner.check(/[,}]/)
        @context.pop
        return colon_found ? '' : :inferred_true
      end

      # Delegate to the main JSON value parser.
      value = parse_json
      @context.pop

      # If parse_json returned JSON_STOP_TOKEN (nothing found due to garbage->terminator),
      # treat it as nil (null) for object values to be safe.
      value == JSON_STOP_TOKEN ? nil : value
    end

    # Encapsulates the logic for merging an array that appears without a key.
    def try_to_merge_dangling_array(object)
      return false unless peek_char == '['

      prev_key = object.keys.last
      return false unless prev_key && object[prev_key].is_a?(Array)

      @scanner.getch # Consume '['
      new_array = parse_array
      return false unless new_array.is_a?(Array)

      to_merge = new_array.length == 1 && new_array.first.is_a?(Array) ? new_array.first : new_array
      object[prev_key].concat(to_merge)

      skip_whitespaces
      @scanner.skip(',')
      skip_whitespaces

      true
    end

    # Parses a JSON array from the string.
    # Assumes the opening '[' has already been consumed by the caller.
    # This is a lenient parser designed to handle malformed JSON.
    def parse_array
      arr = []
      @context.push(:array)
      char = peek_char
      # Stop when you find the closing bracket or an invalid character like '}'
      while !@scanner.eos? && ![']', '}'].include?(char)
        skip_whitespaces
        char = peek_char

        # Check for comments explicitly inside array to avoid recursion or garbage consumption issues
        if ['#', '/'].include?(char)
          parse_comment
          char = peek_char
          next
        end

        value = ''
        if STRING_DELIMITERS.include?(char)
          # Sometimes it can happen that LLMs forget to start an object and then you think it's a string in an array
          # So we are going to check if this string is followed by a : or not
          # And either parse the string or parse the object
          i = 1
          i = skip_to_character(char, start_idx: i)
          i = skip_whitespaces_at(start_idx: i + 1)
          value = (peek_char(i) == ':' ? parse_object : parse_string)
        else
          value = parse_json
        end

        # Handle JSON_STOP_TOKEN from parse_json (EOS or consumed terminator)
        if value == JSON_STOP_TOKEN
          # Do nothing, just skipped garbage
        elsif strictly_empty?(value)
          # Only consume if we didn't just hit a terminator that parse_json successfully respected
          @scanner.getch unless value.nil? && ['}', ']'].include?(peek_char)
        elsif value == '...' && @scanner.string.getbyte(@scanner.pos - 1) == 46
          # just skip if the previous byte was a dot (46)
        else
          arr << value
        end

        char = peek_char
        while char && char != ']' && (char.match?(/\s/) || char == ',')
          @scanner.getch
          char = peek_char
        end
      end

      # Handle a potentially missing closing bracket, a common LLM error.
      unless @scanner.scan(']')
        @scanner.scan('}') # Consume } if it was the closer
      end
      @context.pop

      arr
    end

    # Parses a JSON string. This is a very lenient parser designed to handle
    # many common errors found in LLM-generated JSON, such as missing quotes,
    # incorrect escape sequences, and ambiguous string terminators
    def parse_string
      char = peek_char

      # Consume comments that appear before the string starts
      while ['#', '/'].include?(char)
        parse_comment
        char = peek_char
      end

      doubled_quotes = false
      missing_quotes = false
      lstring_delimiter = rstring_delimiter = '"'

      # A valid string can only start with a valid quote or, in our case, with a literal
      while !@scanner.eos? && !STRING_DELIMITERS.include?(char) && !char.match?(/[\p{L}0-9]/)
        return '' if ['{', '}', '[', ']', ':', ','].include?(char)

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
        if %w[t f n].include?(char.downcase) && !current_context?(:object_key)
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
          current_context?(:object_key) && next_value == ':'
        ) || (
          current_context?(:object_value) && [',', '}'].include?(next_value)
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

      string_parts = []

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
          break if current_context?(:object_key) && (char == ':' || char.match?(/\s/))
          break if current_context?(:object_key) && [']', '}'].include?(char)
          break if current_context?(:array) && [']', ','].include?(char)
        end

        if current_context?(:object_value) && [',', '}'].include?(char) &&
           (string_parts.empty? || string_parts.last != rstring_delimiter)
          rstring_delimiter_missing = true
          # check if this is a case in which the closing comma is NOT missing instead
          skip_whitespaces
          if peek_char(1) == '\\'
            # Ok this is a quoted string, skip
            rstring_delimiter_missing = false
          end

          i = skip_to_character(rstring_delimiter, start_idx: 1)
          next_c = peek_char(i)

          is_gap_clean = true
          is_gap_clean = (1...i).all? { |k| peek_char(k)&.match?(/\s/) } if missing_quotes && next_c

          if next_c && is_gap_clean
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
                rstring_delimiter_missing = false if next_c && next_c != ':'
              end
            end
          elsif next_c
            rstring_delimiter_missing = false
          else
            # There could be a case in which even the next key:value is missing delimeters
            # because it might be a systemic issue with the output
            # So let's check if we can find a : in the string instead
            i = skip_to_character(':', start_idx: 1)
            next_c = peek_char(i)
            break if next_c

            # OK then this is a systemic issue with the output

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
              # Check for an unmatched opening brace in string_parts
              string_parts.reverse_each do |c|
                next unless c == '{'

                # Ok then this is part of the string
                rstring_delimiter_missing = false
                break
              end
            end

          end

          break if rstring_delimiter_missing
        end

        if char == ']' && context_contain?(:array) && string_parts.last != rstring_delimiter
          i = skip_to_character(rstring_delimiter)
          # No delimiter found
          break unless peek_char(i)
        end

        if current_context?(:object_value) && char == '}'
          # We found the end of an object while parsing a value
          # Check if the object is really over, to avoid doubling the closing brace
          i = skip_whitespaces_at(start_idx: 1)
          next_c = peek_char(i)
          break unless next_c
        end

        string_parts << char
        @scanner.getch # Consume the character
        char = peek_char

        if !@scanner.eos? && string_parts.last == '\\'
          # This is a special case, if people use real strings this might happen
          if [rstring_delimiter, 't', 'n', 'r', 'b', '\\'].include?(char)
            string_parts.pop
            string_parts << ESCAPE_MAPPING.fetch(char, char)

            @scanner.getch # Consume the character
            char = peek_char
            while !@scanner.eos? && string_parts.last == '\\' && [rstring_delimiter, '\\'].include?(char)
              # this is a bit of a special case, if I don't do this it will close the loop or create a train of \\
              # I don't love it though
              string_parts.pop
              string_parts << char
              @scanner.getch # Consume the character
              char = peek_char
            end
            next
          elsif %w[u x].include?(char)
            num_chars = (char == 'u' ? 4 : 2)
            saved_pos = @scanner.pos
            hex_parts = []

            # Use getch in loop to correctly extract chars (handling multibyte)
            num_chars.times do
              c = @scanner.getch
              break unless c

              hex_parts << c
            end

            @scanner.pos = saved_pos

            if hex_parts.length == num_chars && hex_parts.all? { |c| '0123456789abcdefABCDEF'.include?(c) }
              string_parts.pop
              string_parts << hex_parts.join.to_i(16).chr('UTF-8')

              # Advance scanner past the hex digits.
              # Since hex digits are ASCII, pos += num_chars + 1 (for u/x) works.
              @scanner.pos += num_chars + 1

              char = peek_char
              next
            end
          elsif STRING_DELIMITERS.include?(char) && char != rstring_delimiter
            string_parts.pop
            string_parts << char
            @scanner.getch # Consume the character
            char = peek_char
            next
          end
        end

        # If we are in object key context and we find a colon, it could be a missing right quote
        if char == ':' && !missing_quotes && current_context?(:object_key)
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

        if char == rstring_delimiter && string_parts.last != '\\'
          if doubled_quotes && peek_char(1) == rstring_delimiter
            @scanner.getch
          elsif missing_quotes && current_context?(:object_value)
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
            string_parts << char.to_s
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
                   current_context?(:object_value) &&
                   next_c == ','
                 )
                break
              end

              i += 1
              next_c = peek_char(i)
            end

            # If we stopped for a comma in object_value context, let's check if find a "} at the end of the string
            if next_c == ',' && current_context?(:object_value)
              i += 1
              i = skip_to_character(rstring_delimiter, start_idx: i)
              next_c = peek_char(i)
              # Ok now I found a delimiter, let's skip whitespaces and see if next we find a } or a ,
              i += 1
              i = skip_whitespaces_at(start_idx: i)
              next_c = peek_char(i)
              if ['}', ','].include?(next_c)
                string_parts << char.to_s
                @scanner.getch # Consume the character
                char = peek_char
                next
              end
            elsif next_c == rstring_delimiter && peek_char(i - 1) != '\\'
              # Check if self.index:self.index+i is only whitespaces, break if that's the case
              break if (1..i).all? { |j| peek_char(j).to_s.match(/\s/) }

              if current_context?(:object_value)
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
                    string_parts << char.to_s
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
                  string_parts << char.to_s
                  @scanner.getch # Consume the character
                  char = peek_char
                end
              elsif current_context?(:array)
                # Heuristic: Check if this quote is a closer or internal.
                # 1. Find the NEXT delimiter (quote) index `j`.
                j = 1
                found_next = false
                while (c = peek_char(j))
                  if c == rstring_delimiter
                    # Check if escaped (count preceding backslashes)
                    bk = 1
                    slashes = 0
                    while j - bk >= 0 && peek_char(j - bk) == '\\'
                      slashes += 1
                      bk += 1
                    end
                    if slashes.even?
                      found_next = true
                      break
                    end
                  end
                  j += 1
                end

                # 2. Check conditions to STOP (treat as closing quote):
                #    a) Strictly whitespace between quotes: ["a" "b"]
                is_whitespace = (1...j).all? { |k| peek_char(k).match?(/\s/) }

                #    b) Next quote is followed by a separator: ["val1" val2",]
                is_next_closer = false
                if found_next
                  k = j + 1
                  k += 1 while peek_char(k)&.match?(/\s/) # skip whitespaces
                  is_next_closer = [',', ']', '}'].include?(peek_char(k))
                end

                unless is_whitespace || is_next_closer
                  unmatched_delimiter = !unmatched_delimiter
                  string_parts << char.to_s
                  @scanner.getch # Consume the character
                  char = peek_char
                  next
                end

                break
              elsif current_context?(:object_key)
                string_parts << char.to_s
                @scanner.getch # Consume the character
                char = peek_char
              end
            end
          end

        end
      end

      if !@scanner.eos? && missing_quotes && current_context?(:object_key) && char.match(/\s/)
        skip_whitespaces
        return '' unless [':', ','].include?(peek_char)
      end

      # A fallout of the previous special case in the while loop,
      # we need to update the index only if we had a closing quote
      if char == rstring_delimiter
        @scanner.getch
      elsif missing_quotes && current_context?(:object_key) && string_parts.last == ','
        string_parts.pop
      end

      final_str = string_parts.join
      final_str = final_str.rstrip if missing_quotes || final_str.end_with?("\n")

      final_str
    end

    # Parses a JSON number, which can be an integer or a floating-point value.
    # This parser is lenient and will also handle currency-like strings with commas,
    # returning them as a string. It attempts to handle various malformed number
    # inputs that might be generated by LLMs
    def parse_number
      # OPTIMIZE: Use pre-compiled regex based on context
      regex = current_context?(:array) ? NUMBER_NO_COMMA_REGEX : NUMBER_REGEX

      scanned_str = @scanner.scan(regex)
      return nil unless scanned_str

      # Handle cases where the number ends with an invalid character.
      if !scanned_str.empty? && ['-', 'e', 'E', ','].include?(scanned_str[-1])
        # Do not rewind scanner, simply discard the invalid trailing char (garbage)
        scanned_str = scanned_str[0...-1]
      # Handle cases where what looked like a number is actually a string.
      # e.g., "123-abc"
      elsif peek_char&.match?(/\p{L}/)
        # Roll back the entire scan and re-parse as a string.
        @scanner.pos -= scanned_str.bytesize
        return parse_string
      end

      # Sometimes numbers are followed by a quote, which is garbage
      @scanner.getch if peek_char == '"'

      # Attempt to convert the string to the appropriate number type.
      # Use rescue to handle conversion errors gracefully, returning the original string.
      begin
        # Fix for Ruby < 3.4: "1." is not a valid float.
        # If it ends with '.', we strip the dot and force Float conversion
        # to ensure "1." becomes 1.0 (Float) instead of 1 (Integer).
        if scanned_str.end_with?('.')
          Float(scanned_str[0...-1])
        elsif scanned_str.include?(',')
          Float(scanned_str.tr(',', '.'))
        elsif scanned_str.match?(/[.eE]/)
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
    # After skipping the comment, it returns, allowing the caller to loop.
    def parse_comment
      # Check for a block comment `/* ... */`
      if @scanner.scan(%r{/\*})
        # Scan until the closing delimiter is found.
        # The `lazy` quantifier `*?` ensures we stop at the *first* `*/`.
        @scanner.scan_until(%r{\*/}) || @scanner.terminate

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
        # consume this single stray character before exiting
        @scanner.getch
      end

      skip_whitespaces
    end

    # This function is a non-destructive lookahead.
    # It quickly iterates to find a character, handling escaped characters, and
    # returns the index (offset) from the scanner
    def skip_to_character(characters, start_idx: 0)
      pattern = characters.is_a?(Array) ? Regexp.union(characters) : characters

      saved_pos = @scanner.pos
      # Skip start_idx
      start_idx.times { @scanner.getch }

      # Track accumulated length in chars
      acc_len = start_idx
      found_idx = nil

      while (matched_text = @scanner.scan_until(pattern))
        chunk_len = matched_text.length
        delimiter_len = @scanner.matched.length

        # Check escapes
        # matched_text ends with delimiter.
        # Check chars before the last one.
        content_before = matched_text[0...-delimiter_len]
        bs_count = 0
        idx = content_before.length - 1
        while idx >= 0 && content_before[idx] == '\\'
          bs_count += 1
          idx -= 1
        end

        if bs_count.even?
          # Found it
          found_idx = acc_len + (chunk_len - delimiter_len)
          break
        else
          # Escaped, continue
          acc_len += chunk_len
        end
      end

      if found_idx.nil?
        # Not found. Return remaining distance.
        # We scanned to EOS (if loop finished) or stopped.
        found_idx = acc_len + @scanner.rest.length
      end

      @scanner.pos = saved_pos
      found_idx
    end

    # This function uses the StringScanner to skip whitespace from the current position.
    # It is more efficient and idiomatic than manual index management
    def skip_whitespaces_at(start_idx: 0)
      saved_pos = @scanner.pos
      start_idx.times { @scanner.getch }

      # Check forward for non-whitespace
      matched = @scanner.check_until(/\S/)

      res = if matched
              # matched contains spaces then one non-space.
              # The index of that non-space (relative to current pos after start_idx)
              # is matched.length - 1
              (matched.length - 1) + start_idx
            else
              # No non-space found.
              @scanner.rest.length + start_idx
            end

      @scanner.pos = saved_pos
      res
    end

    # Helper to check if two objects are of the same container type (Array or Hash).
    def same_object_type?(obj1, obj2)
      (obj1.is_a?(Array) && obj2.is_a?(Array)) || (obj1.is_a?(Hash) && obj2.is_a?(Hash))
    end

    def strictly_empty?(value)
      # Check if the value is a container AND if it's empty.
      case value
      when String, Array, Hash, Set
        value.empty?
      else
        false
      end
    end

    # Skips whitespaces
    def skip_whitespaces
      @scanner.skip(/\s+/)
    end

    # Peeks the next character without advancing the scanner
    def peek_char(offset = 0)
      return @scanner.check(/./m) if offset.zero?

      saved_pos = @scanner.pos
      c = nil
      (offset + 1).times do
        c = @scanner.getch
        break if c.nil?
      end
      @scanner.pos = saved_pos
      c
    end

    def current_context?(value)
      @context&.last == value
    end

    def context_contain?(value)
      @context.include?(value)
    end

    # Checks if the character signifies the start of a string or literal
    def string_start?(char)
      STRING_DELIMITERS.include?(char) || char&.match?(/\p{L}/)
    end

    # Checks if the character signifies the start of a number
    def number_start?(char)
      char&.match?(/\d/) || char == '-' || char == '.'
    end
  end
end
