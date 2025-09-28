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
          expected_output: JSON.dump({ key: 'value☺' })
        },
        {
          input: '{"key": "value\\nvalue"}',
          expected_output: JSON.dump({ key: "value\nvalue" })
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
          expected_output: JSON.dump({ key: 'value☺' })
        },
        {
          input: '{"key": "value\\nvalue"}',
          expected_output: JSON.dump({ key: "value\nvalue" })
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

    context 'when provided json with numbers and return object' do
      [
        {
          input: '1',
          expected_output: 1
        },
        {
          input: '1.2',
          expected_output: 1.2
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input], return_objects: true)).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with numbers' do
      [
        {
          input: ' - { "test_key": ["test_value", "test_value2"] }',
          expected_output: JSON.dump({ test_key: %w[test_value test_value2] })
        },
        {
          input: '{"key": 1/3}',
          expected_output: JSON.dump({ key: '1/3' })
        },
        {
          input: '{"key": .25}',
          expected_output: JSON.dump({ key: 0.25 })
        },
        {
          input: '{"here": "now", "key": 1/3, "foo": "bar"}',
          expected_output: JSON.dump({ here: 'now', key: '1/3', foo: 'bar' })
        },
        {
          input: '{"key": 12345/67890}',
          expected_output: JSON.dump({ key: '12345/67890' })
        },
        {
          input: '[105,12',
          expected_output: JSON.dump([105, 12])
        },
        {
          input: '{"key": 105,12,',
          expected_output: JSON.dump({ key: 105.12 })
        },
        {
          input: '{"key", 105,12,',
          expected_output: JSON.dump({ key: true, '105,12': true })
        },
        {
          input: '{"key": 1/3, "foo": "bar"}',
          expected_output: JSON.dump({ key: '1/3', foo: 'bar' })
        },
        {
          input: '{"key": 10-20}',
          expected_output: JSON.dump({ key: '10-20' })
        },
        {
          input: '{"key": 1.1.1}',
          expected_output: JSON.dump({ key: '1.1.1' })
        },
        {
          input: '{"key": 1. }',
          expected_output: JSON.dump({ key: 1.0 })
        },
        {
          input: '{"key": 1e10 }',
          expected_output: JSON.dump({ key: 10_000_000_000.0 })
        },
        {
          input: '{"key": 1e }',
          expected_output: JSON.dump({ key: 1 })
        },
        {
          input: '{"key": 1notanumber }',
          expected_output: JSON.dump({ key: '1notanumber' })
        },
        {
          input: '[1, 2notanumber]',
          expected_output: JSON.dump([1, '2notanumber'])
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided string' do
      [
        {
          input: '"',
          expected_output: '""'
        },
        {
          input: "\n",
          expected_output: ''
        },
        {
          input: ' ',
          expected_output: ''
        },
        {
          input: 'string',
          expected_output: ''
        },
        {
          input: 'stringbeforeobject {}',
          expected_output: '{}'
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with strings' do
      [
        {
          input: "{'key': 'string', 'key2': false, \"key3\": null, \"key4\": unquoted}",
          expected_output: JSON.dump({ key: 'string', key2: false, key3: nil, key4: 'unquoted' })
        },
        {
          input: '{"name": "John", "age": 30, "city": "New York',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York' })
        },
        {
          input: '{"name": "John", "age": 30, city: "New York"}',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York' })
        },
        {
          input: '{"name": "John", "age": 30, "city": New York}',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York' })
        },
        {
          input: '{"name": John, "age": 30, "city": "New York"}',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York' })
        },
        {
          input: '{“slanted_delimiter”: "value"}',
          expected_output: JSON.dump({ slanted_delimiter: 'value' })
        },
        {
          input: '{"name": "John", "age": 30, "city": "New',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New' })
        },
        {
          input: '{"name": "John", "age": 30, "city": "New York, "gender": "male"}',
          expected_output: JSON.dump({ name: 'John', age: 30, city: 'New York', gender: 'male' })
        },
        {
          input: '[{"key": "value", COMMENT "notes": "lorem "ipsum", sic." }]',
          expected_output: JSON.dump([{ key: 'value', notes: 'lorem "ipsum", sic.' }])
        },
        {
          input: '{"key": ""value"}',
          expected_output: JSON.dump({ key: 'value' })
        },
        {
          input: '{"key": "value", 5: "value"}',
          expected_output: JSON.dump({ key: 'value', '5' => 'value' })
        },
        {
          input: '{"foo": "\\"bar\\""',
          expected_output: JSON.dump({ foo: '"bar"' })
        },
        {
          input: '{"" key":"val"',
          expected_output: JSON.dump({ ' key' => 'val' })
        },
        {
          input: '{"key": value "key2" : "value2" ',
          expected_output: JSON.dump({ key: 'value', key2: 'value2' })
        },
        {
          input: '{"key": "lorem ipsum ... "sic " tamet. ...}',
          expected_output: JSON.dump({ key: 'lorem ipsum ... "sic " tamet. ...' })
        },
        {
          input: '{"key": value , }',
          expected_output: JSON.dump({ key: 'value' })
        },
        {
          input: '{"comment": "lorem, "ipsum" sic "tamet". To improve"}',
          expected_output: JSON.dump({ comment: 'lorem, "ipsum" sic "tamet". To improve' })
        },
        {
          input: '{"key": "v"alu"e"} key:',
          expected_output: JSON.dump({ key: 'v"alu"e' })
        },
        {
          input: '{"key": "v"alue", "key2": "value2"}',
          expected_output: JSON.dump({ key: 'v"alue', key2: 'value2' })
        },
        {
          input: '[{"key": "v"alu,e", "key2": "value2"}]',
          expected_output: JSON.dump([{ key: 'v"alu,e', key2: 'value2' }])
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with string escaping' do
      [
        {
          input: "'\"'",
          expected_output: ''
        },
        {
          input: '{"key": \'string"\n\t\\le\'',
          expected_output: JSON.dump({ key: "string\"\n\t\\le" })
        },
        {
          input: ' ',
          expected_output: ''
        },
        {
          input: 'string',
          expected_output: ''
        },
        {
          input: 'stringbeforeobject {}',
          expected_output: '{}'
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with object edge cases', :skip do
      [
        {
          input: '{foo: [}',
          expected_output: JSON.dump({ foo: [] })
        },
        {
          input: '{       ',
          expected_output: JSON.dump({})
        },
        {
          input: '{"": "value"',
          expected_output: JSON.dump({ "": 'value' })
        },
        {
          input: '{"value_1": true, COMMENT "value_2": "data"}',
          expected_output: JSON.dump({ value_1: true, value_2: 'data' })
        },
        {
          input: '{"value_1": true, SHOULD_NOT_EXIST "value_2": "data" AAAA }',
          expected_output: JSON.dump({ value_1: true, value_2: 'data' })
        },
        {
          input: '{"" : true, "key2": "value2"}',
          expected_output: JSON.dump({ "": true, key2: 'value2' })
        },
        {
          input: '{"words": abcdef", "numbers": 12345", "words2": ghijkl" }',
          expected_output: JSON.dump({ words: 'abcdef', numbers: 12_345, words2: 'ghijkl' })
        },
        {
          input: '{"number": 1,"reason": "According...""ans": "YES"}',
          expected_output: JSON.dump({ number: 1, reason: 'According...', ans: 'YES' })
        },
        {
          input: '{ "a" : "{ b": {} }" }',
          expected_output: JSON.dump({ a: '{ b' })
        },
        {
          input: '{"b": "xxxxx" true}',
          expected_output: JSON.dump({ b: 'xxxxx' })
        },
        {
          input: '{"key": "Lorem "ipsum" s,"}',
          expected_output: JSON.dump({ key: 'Lorem "ipsum" s,' })
        },
        {
          input: '{"lorem": ipsum, sic, datum.",}',
          expected_output: JSON.dump({ lorem: 'ipsum, sic, datum.' })
        },
        {
          input: '{"lorem": sic tamet. "ipsum": sic tamet, quick brown fox. "sic": ipsum}',
          expected_output: JSON.dump({ lorem: 'sic tamet.', ipsum: 'sic tamet', sic: 'ipsum' })
        },
        {
          input: '{"lorem_ipsum": "sic tamet, quick brown fox. }',
          expected_output: JSON.dump({ lorem_ipsum: 'sic tamet, quick brown fox.' })
        },
        {
          input: '{"key":value, " key2":"value2" }',
          expected_output: JSON.dump({ key: 'value', ' key2': 'value2' })
        },
        {
          input: '{"key":value "key2":"value2" }',
          expected_output: JSON.dump({ key: 'value', key2: 'value2' })
        },
        {
          input: "{'text': 'words{words in brackets}more words'}",
          expected_output: JSON.dump({ text: 'words{words in brackets}more words' })
        },
        {
          input: '{text:words{words in brackets}}',
          expected_output: JSON.dump({ text: 'words{words in brackets}' })
        },
        {
          input: '{text:words{words in brackets}m}',
          expected_output: JSON.dump({ text: 'words{words in brackets}m' })
        },
        {
          input: '{"key": "value, value2"```',
          expected_output: JSON.dump({ key: 'value, value2' })
        },
        {
          input: '{key:value,key2:value2}',
          expected_output: JSON.dump({ key: 'value', key2: 'value2' })
        },
        {
          input: '{"key:"value"}',
          expected_output: JSON.dump({ key: 'value' })
        },
        {
          input: '{"key:value}',
          expected_output: JSON.dump({ key: 'value' })
        },
        {
          input: '[{"lorem": {"ipsum": "sic"}, """" "lorem": {"ipsum": "sic"}]',
          expected_output: JSON.dump([{ lorem: { ipsum: 'sic' } }, { lorem: { ipsum: 'sic' } }])
        },
        {
          input: '{ "key": ["arrayvalue"], ["arrayvalue1"], ["arrayvalue2"], "key3": "value3" }',
          expected_output: JSON.dump({ key: %w[arrayvalue arrayvalue1 arrayvalue2], key3: 'value3' })
        },
        {
          input: '{ "key": ["arrayvalue"], "key3": "value3", ["arrayvalue1"] }',
          expected_output: JSON.dump({ key: ['arrayvalue'], key3: 'value3', arrayvalue1: '' })
        },
        {
          input: '{"key": "{\\\\"key\\\\\\":[\\"value\\\\\\"],\\"key2\\":"value2"}"}',
          expected_output: JSON.dump({ key: '{\"key\":[\"value\"],\"key2\":\"value2\"}' })
        },
        {
          input: '{"key": , "key2": "value2"}',
          expected_output: JSON.dump({ key: '', key2: 'value2' })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with array edge cases', :skip do
      [
        {
          input: '[{]',
          expected_output: JSON.dump([])
        },
        {
          input: '[',
          expected_output: JSON.dump([])
        },
        {
          input: '["',
          expected_output: JSON.dump([])
        },
        {
          input: ']',
          expected_output: ''
        },
        {
          input: '[1, 2, 3,',
          expected_output: JSON.dump([1, 2, 3])
        },
        {
          input: '[1, 2, 3, ...]',
          expected_output: JSON.dump([1, 2, 3])
        },
        {
          input: '[1, 2, ... , 3]',
          expected_output: JSON.dump([1, 2, 3])
        },
        {
          input: "[1, 2, '...', 3]",
          expected_output: JSON.dump([1, 2, '...', 3])
        },
        {
          input: '[true, false, null, ...]',
          expected_output: JSON.dump([true, false, nil])
        },
        {
          input: '["a" "b" "c" 1',
          expected_output: JSON.dump(['a', 'b', 'c', 1])
        },
        {
          input: '{"employees":["John", "Anna",',
          expected_output: JSON.dump({ 'employees' => %w[John Anna] })
        },
        {
          input: '{"employees":["John", "Anna", "Peter"',
          expected_output: JSON.dump({ 'employees' => %w[John Anna Peter] })
        },
        {
          input: '{"key1": {"key2": [1, 2, 3',
          expected_output: JSON.dump({ 'key1' => { 'key2' => [1, 2, 3] } })
        },
        {
          input: '{"key": ["value]}',
          expected_output: JSON.dump({ 'key' => ['value'] })
        },
        {
          input: '["lorem "ipsum" sic"]',
          expected_output: JSON.dump(['lorem "ipsum" sic'])
        },
        {
          input: '{"key1": ["value1", "value2"}, "key2": ["value3", "value4"]}',
          expected_output: JSON.dump({ 'key1' => %w[value1 value2], 'key2' => %w[value3 value4] })
        },
        {
          input: '{"key": ["value" "value1" "value2"]}',
          expected_output: JSON.dump({ 'key' => %w[value value1 value2] })
        },
        {
          input: '{"key": ["lorem "ipsum" dolor "sit" amet, "consectetur" ", "lorem "ipsum" dolor", "lorem"]}',
          expected_output: JSON.dump({ key: ['lorem "ipsum" dolor "sit" amet, "consectetur" ',
                                             'lorem "ipsum" dolor', 'lorem'] })
        },
        {
          input: '{"k"e"y": "value"}',
          expected_output: JSON.dump({ 'k"e"y' => 'value' })
        },
        {
          input: '["key":"value"}]',
          expected_output: JSON.dump([{ 'key' => 'value' }])
        },
        {
          input: '[{"key": "value", "key"',
          expected_output: JSON.dump([{ 'key' => 'value' }])
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided json with arrays with missing quotes' do
      [
        {
          input: '["value1" value2", "value3"]',
          expected_output: JSON.dump(%w[value1 value2 value3])
        },
        {
          input: '{"bad_one":["Lorem Ipsum", "consectetur" comment" ], "good_one":[ "elit", "sed", "tempor"]}',
          expected_output: JSON.dump({ 'bad_one' => ['Lorem Ipsum', 'consectetur', 'comment'],
                                       'good_one' => %w[elit sed tempor] })
        },
        {
          input: '{"bad_one": ["Lorem Ipsum","consectetur" comment],"good_one": ["elit","sed","tempor"]}',
          expected_output: JSON.dump({ 'bad_one' => ['Lorem Ipsum', 'consectetur', 'comment'],
                                       'good_one' => %w[elit sed tempor] })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end
  end
end
