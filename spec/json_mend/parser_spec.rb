# frozen_string_literal: true

RSpec.describe JsonMend::Parser do
  describe '#parse' do
    subject { parser.parse }

    let(:parser) { described_class.new(input) }

    # Requirement: Allow // and /**/ comments
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

    # Requirement: Allow unescaped newlines
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

    # Requirement: Allow trailing commas
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
  end
end
