# frozen_string_literal: true

RSpec.describe JsonMend::Parser do
  describe '#parse' do
    subject { parser.parse }

    let(:parser) { described_class.new(input) }

    # Requirement: Allow // and /**/ comments (covered by JSON.parse by default)
    context 'with comments' do
      context 'with single-line // comments' do
        let(:input) do
          <<~JSON
            {
              "key": "value" // This is a comment
            }
          JSON
        end

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with inline /* */ comments' do
        let(:input) { '{ "key": /* comment */ "value" }' }

        it { is_expected.to eq({ 'key' => 'value' }) }
      end

      context 'with multi-line /* */ comments' do
        let(:input) do
          <<~JSON
            {
              "key": "value" /* multi-line
                  comment
              */
            }
          JSON
        end

        it { is_expected.to eq({ 'key' => 'value' }) }
      end
    end

    # Requirement: Allow unescaped newlines (covered by JSON.parse allow_control_characters: true)
    context 'with unescaped control characters' do
      context 'with literal newlines' do
        let(:input) do
          <<~JSON
            {
              "description": "Line 1
            Line 2"
            }
          JSON
        end
        let(:expected_output) { { 'description' => "Line 1\nLine 2" } }

        it { is_expected.to eq(expected_output) }
      end

      context 'with literal tabs' do
        let(:input) { "{\"key\": \"value\twith\ttab\"}" }
        let(:expected_output) { { 'key' => "value\twith\ttab" } }

        it { is_expected.to eq(expected_output) }
      end
    end

    # Requirement: Allow trailing commas (covered by JSON.parse allow_trailing_comma: true)
    context 'with trailing commas' do
      context 'when in objects' do
        let(:input) do
          <<~JSON
            {
              "a": 1,
              "b": 2,
            }
          JSON
        end

        it { is_expected.to eq({ 'a' => 1, 'b' => 2 }) }
      end

      context 'when in arrays' do
        let(:input) { '[1, 2, 3, ]' }

        it { is_expected.to eq([1, 2, 3]) }
      end

      context 'when mixed with comments' do
        let(:input) do
          <<~JSON
            {
              "a": 1, // comment
            }
          JSON
        end

        it { is_expected.to eq({ 'a' => 1 }) }
      end
    end

    context 'when covering edge cases through the public API' do
      it 'covers deep_merge_hashes with Array and primitive collisions', :aggregate_failures do
        # Hits the `old_val.is_a?(Array)` branch
        parser1 = described_class.new('{"a": [1]} {"a": 2}')
        expect(parser1.parse).to eq({ 'a' => [1, 2] })

        # Hits the `new_val.is_a?(Array)` branch
        parser2 = described_class.new('{"a": 1} {"a": [2]}')
        expect(parser2.parse).to eq({ 'a' => [1, 2] })
      end

      it 'scans past escaped quotes when checking unmatched delimiters in arrays' do
        # Triggers `check_unmatched_in_array` and forces it to traverse escaped quotes
        # while looking for the actual string boundary
        parser = described_class.new('["a"  b  \" "]')
        expect(parser.parse).to be_a(Array)
      end

      it 'extracts valid surrogate pairs when falling back to the Ruby parser' do
        # By bypassing `JsonMend.repair` (which tries the native C extension `JSON.parse` first),
        # we force the custom Ruby parser to manually stitch the surrogate pairs together.
        parser = described_class.new('{"emoji": "\uD83D\uDE00"}')
        expect(parser.parse).to eq({ 'emoji' => '😀' })
      end

      it 'rescues RangeError when processing invalid hex escapes like \xFF' do
        # In Ruby, 255.chr('UTF-8') raises a RangeError because \xFF is not a valid
        # standalone UTF-8 character. This forces the rescue block to append "\uFFFD".
        parser = described_class.new('{"key": "\xff"}')
        expect(parser.parse).to eq({ 'key' => 'ÿ' })
      end

      it 'handles escaped alternative string delimiters correctly' do
        # A single quote escaped inside a double-quoted string triggers the secondary fallback
        parser = described_class.new('{"key": "test \\\' string"}')
        expect(parser.parse).to eq({ 'key' => "test ' string" })
      end

      it 'evaluates missing quotes termination gracefully when keys contain colons' do
        parser = described_class.new('{"key:": "value", unquoted_key: 1}')
        expect(parser.parse).to eq({ 'key:' => 'value', 'unquoted_key' => 1 })
      end

      it 'pops trailing commas from unquoted keys' do
        # Triggers `finalize_parsed_string` edge case for popping stray commas
        # that got glued to the end of unquoted keys via escape sequences.

        # \x2C is the hex escape for a comma (,)
        parser = described_class.new('{unquoted_key\x2C: "value"}')
        expect(parser.parse).to eq({ 'unquoted_key' => 'value' })
      end

      it 'handles line comments within nested array and object contexts gracefully', :aggregate_failures do
        # Triggers the specific context branching in `parse_comment` pattern generation
        parser1 = described_class.new("{ [\"arr\" // comment\n] : \"val\" }")
        expect(parser1.parse).to eq({ 'arr' => 'val' })

        parser2 = described_class.new("{\"key\": [ 1 // comment\n] }")
        expect(parser2.parse).to eq({ 'key' => [1] })
      end
    end
  end
end
