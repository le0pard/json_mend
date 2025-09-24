# frozen_string_literal: true

RSpec.describe JsonMend do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end

  describe '.repair' do
    context 'when provided valid json' do
      [
        {
          input: '{"name": "John", "age": 30, "city": "New York"}',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York' })
        },
        {
          input: '{"employees":["John", "Anna", "Peter"]} ',
          expected_output: JSON.dump({ employees: %w[John Anna Peter] })
        },
        {
          input: '{"key": "value:value"}',
          expected_output: JSON.dump({ key: 'value:value' })
        },
        {
          input: '{"text": "The quick brown fox,"}',
          expected_output: JSON.dump({ text: 'The quick brown fox,' })
        },
        {
          input: '{"text": "The quick brown fox won\'t jump"}',
          expected_output: JSON.dump({ text: "The quick brown fox won't jump" })
        },
        {
          input: '{"key": ""',
          expected_output: JSON.dump({ key: '' })
        },
        {
          input: '{"key1": {"key2": [1, 2, 3]}}',
          expected_output: JSON.dump({ key1: { key2: [1, 2, 3] } })
        },
        {
          input: '{"key": 12345678901234567890}',
          expected_output: JSON.dump({ key: 12_345_678_901_234_567_890 })
        },
        {
          input: '{"key": "value\u263a"}',
          expected_output: JSON.dump({ key: 'value\\u263a' })
        },
        {
          input: '{"key": "value\\nvalue"}',
          expected_output: JSON.dump({ key: 'value\\nvalue' })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided multiple json' do
      [
        {
          input: '[]{}',
          expected_output: JSON.dump([[], {}])
        },
        {
          input: '{}[]{}',
          expected_output: JSON.dump([{}, [], {}])
        },
        {
          input: '{"key":"value"}[1,2,3,True]',
          expected_output: JSON.dump([{ key: 'value' }, [1, 2, 3, true]])
        },
        {
          input: 'lorem ```json {"key":"value"} ``` ipsum ```json [1,2,3,True] ``` 42',
          expected_output: JSON.dump([{ key: 'value' }, [1, 2, 3, true], 42])
        },
        {
          input: '[{"key":"value"}][{"key":"value_after"}]',
          expected_output: JSON.dump([{ key: 'value_after' }])
        },
        {
          input: '{"key": ""',
          expected_output: JSON.dump({ key: '' })
        },
        {
          input: '{"key1": {"key2": [1, 2, 3]}}',
          expected_output: JSON.dump({ key1: { key2: [1, 2, 3] } })
        },
        {
          input: '{"key": 12345678901234567890}',
          expected_output: JSON.dump({ key: 12_345_678_901_234_567_890 })
        },
        {
          input: '{"key": "value\u263a"}',
          expected_output: JSON.dump({ key: 'value\\u263a' })
        },
        {
          input: '{"key": "value\\nvalue"}',
          expected_output: JSON.dump({ key: 'value\\nvalue' })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with ascii symbols' do
      [
        {
          input: "{'test_中国人_ascii':'统一码'}",
          expected_output: JSON.dump({ 'test_中国人_ascii' => '统一码' })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with boolean or null' do
      [
        {
          input: '  {"key": true, "key2": false, "key3": null}',
          expected_output: JSON.dump({ key: true, key2: false, key3: nil })
        },
        {
          input: '{"key": TRUE, "key2": FALSE, "key3": Null}   ',
          expected_output: JSON.dump({ key: true, key2: false, key3: nil })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with boolean or null and return object' do
      [
        {
          input: 'True',
          expected_output: true
        },
        {
          input: 'False',
          expected_output: false
        },
        {
          input: 'Null',
          expected_output: nil
        },
        {
          input: 'true',
          expected_output: true
        },
        {
          input: 'false',
          expected_output: false
        },
        {
          input: 'null',
          expected_output: nil
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input], return_objects: true)).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when have comments in json' do
      [
        {
          input: '/',
          expected_output: ''
        },
        {
          input: '/* comment */ {"key": "value"}',
          expected_output: JSON.dump({ key: 'value' })
        },
        {
          input: '{ "key": { "key2": "value2" // comment }, "key3": "value3" }',
          expected_output: JSON.dump({ key: { key2: 'value2' }, key3: 'value3' })
        },
        {
          input: '{ "key": { "key2": "value2" # comment }, "key3": "value3" }',
          expected_output: JSON.dump({ key: { key2: 'value2' }, key3: 'value3' })
        },
        {
          input: '{ "key": { "key2": "value2" /* comment */ }, "key3": "value3" }',
          expected_output: JSON.dump({ key: { key2: 'value2' }, key3: 'value3' })
        },
        {
          input: '[ "value", /* comment */ "value2" ]',
          expected_output: JSON.dump(%w[value value2])
        },
        {
          input: '{ "key": "value" /* comment',
          expected_output: JSON.dump({ key: 'value' })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end
  end
end
