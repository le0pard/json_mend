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
          expected_output: JSON.dump([[{ key: 'value' }], [{ key: 'value_after' }]])
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
          expected_output: '"\""'
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

    context 'when provided json with object edge cases' do
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
          expected_output: JSON.dump({ 'value_1' => true, 'value_2' => 'data' })
        },
        {
          input: '{"value_1": true, SHOULD_NOT_EXIST "value_2": "data" AAAA }',
          expected_output: JSON.dump({ 'value_1' => true, 'value_2' => 'data' })
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
          expected_output: JSON.dump({
                                       lorem: 'sic tamet.',
                                       ipsum: 'sic tamet, quick brown fox.',
                                       sic: 'ipsum'
                                     })
        },
        {
          input: '{"lorem_ipsum": "sic tamet, quick brown fox. }',
          expected_output: JSON.dump({ lorem_ipsum: 'sic tamet, quick brown fox. ' })
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
          expected_output: JSON.dump([
                                       { 'lorem' => { 'ipsum' => 'sic' }, '' => '' },
                                       { 'lorem' => { 'ipsum' => 'sic' } }
                                     ])
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
          expected_output: JSON.dump({ key: '{"key":["value"],"key2":"value2"}' })
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

    context 'when provided json with array edge cases' do
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
          expected_output: JSON.dump([{ 'key' => 'value' }, 'key'])
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
          expected_output: JSON.dump({
                                       'bad_one' => ['Lorem Ipsum', 'consectetur', 'comment'],
                                       'good_one' => %w[elit sed tempor]
                                     })
        },
        {
          input: '{"bad_one": ["Lorem Ipsum","consectetur" comment],"good_one": ["elit","sed","tempor"]}',
          expected_output: JSON.dump({
                                       'bad_one' => ['Lorem Ipsum', 'consectetur', 'comment'],
                                       'good_one' => %w[elit sed tempor]
                                     })
        }
      ].each do |test_case|
        it "repair #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided tricky edge cases and malformed structures' do
      [
        # Duplicate keys: The parser splits this into two objects [{"k":"v1"}, {"k":"v2"}]
        # The main loop then sees two Hashes and keeps the last one (both_hash? logic)
        {
          input: '{"key": "v1", "key": "v2"}',
          expected_output: JSON.dump({ 'key' => 'v2' })
        },
        # Hexadecimal escape sequences (\xXX)
        {
          input: '{"key": "\\x41\\x42\\x43"}',
          expected_output: JSON.dump({ 'key' => 'ABC' })
        },
        # Literals used as unquoted keys
        {
          input: '{true: "yes", false: "no", null: "void"}',
          expected_output: JSON.dump({ 'true' => 'yes', 'false' => 'no', 'null' => 'void' })
        },
        # Arrays with leading, trailing, and double commas
        {
          input: '[,, 1, , 2,, ]',
          expected_output: JSON.dump([1, 2])
        },
        # Stray colons inside objects (e.g. from missing keys)
        {
          input: '{"a": 1, : "garbage", "b": 2}',
          expected_output: JSON.dump({ 'a' => 1, 'b' => 2 })
        },
        # Dangling array merging occurring multiple times in one object
        {
          input: '{"k1": [1] [2], "k2": [3] [4]}',
          expected_output: JSON.dump({ 'k1' => [1, 2], 'k2' => [3, 4] })
        },
        # Unclosed string at the very end of the file
        {
          input: '{"key": "value_at_eof',
          expected_output: JSON.dump({ 'key' => 'value_at_eof' })
        },
        # Garbage text surrounding valid JSON (Chat logs, headers, etc.)
        {
          input: 'Output: {"data": 1} End of Output',
          expected_output: JSON.dump({ 'data' => 1 })
        },
        # Doubled quotes (common hallucination)
        {
          input: '{""key"": ""value""}',
          expected_output: JSON.dump({ 'key' => 'value' })
        },
        # Malformed numbers behaving as strings
        {
          input: '{"version": 1.2.3}',
          expected_output: JSON.dump({ 'version' => '1.2.3' })
        },
        {
          input: '{"range": 10-20}',
          expected_output: JSON.dump({ 'range' => '10-20' })
        },
        # Multiple objects of the same type: Only the last one is kept
        {
          input: '{"a": 1} {"b": 2}',
          expected_output: JSON.dump({ 'b' => 2 })
        },
        # Multiple objects of different types: All are kept
        {
          input: '{"a": 1} [1, 2] {"b": 2}',
          expected_output: JSON.dump([{ 'a' => 1 }, [1, 2], { 'b' => 2 }])
        }
      ].each do |test_case|
        it "repairs #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when checking for infinite loops and hanging' do
      [
        {
          input: '{"key": "value" : : : : : : : : : :}',
          description: 'repeated stray colons'
        },
        {
          input: '{"key": "value", , , , , , , , , , }',
          description: 'repeated commas'
        },
        {
          input: ('[' * 500) + (']' * 500),
          description: 'deeply nested arrays'
        },
        {
          input: '{"k": [1] [2] [3] [4] [5] [6] [7] [8] [9] [10]}',
          description: 'repeated dangling array merges'
        },
        {
          input: "\"#{'\\\\' * 500}\"",
          description: 'massive backslash sequence'
        },
        {
          input: "{\"k\": \"#{'\\u' * 100}\"}",
          description: 'repeated broken unicode escapes'
        },
        {
          input: "/* #{'*' * 1000}",
          description: 'unclosed block comment with repeating chars'
        },
        {
          input: "{\"key\": \"start_of_string_and_no_end_#{'a' * 1000}",
          description: 'long unclosed string at EOS'
        },
        {
          input: '{"k": ""v"" ""v"" ""v""}',
          description: 'repeated doubled quotes'
        },
        {
          input: "{#{'"": 1, ' * 100}}",
          description: 'repeated empty keys'
        }
      ].each do |test_case|
        it "does not hang on #{test_case[:description]}" do
          expect do
            with_timeout(2) do
              described_class.repair(test_case[:input])
            end
          end.not_to raise_error
        end
      end
    end

    context 'when parsing loose arrays' do
      [
        {
          input: '[1 2 3]',
          expected_output: JSON.dump([1, 2, 3]),
          desc: 'space separated items'
        },
        {
          input: "[\"a\" \"b\"\n\"c\"]",
          expected_output: JSON.dump(%w[a b c]),
          desc: 'mixed whitespace separated items'
        },
        {
          input: '[1, garbage, 2]',
          expected_output: JSON.dump([1, 'garbage', 2]),
          desc: 'unquoted garbage text treated as strings'
        }
      ].each do |tc|
        it "repairs #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when parsing loose objects' do
      [
        {
          input: '{"key" "value"}',
          expected_output: JSON.dump({ 'key" "value' => true }),
          desc: 'missing colon'
        },
        {
          input: '{"key" "value", "key2" 123}',
          expected_output: JSON.dump({ 'key" "value", "key2' => 123 }),
          desc: 'missing colons in multiple pairs'
        },
        {
          input: '{"flag"}',
          expected_output: JSON.dump({ 'flag' => true }),
          desc: 'implicit true for missing value without colon'
        },
        {
          input: '{"flag", "flag2": false}',
          expected_output: JSON.dump({ 'flag", "flag2' => false }),
          desc: 'implicit true mixed with valid pairs'
        },
        {
          input: '{123: "value", true: "value"}',
          expected_output: JSON.dump({ '123' => 'value', 'true' => 'value' }),
          desc: 'literals used as unquoted keys'
        }
      ].each do |tc|
        it "repairs #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when handling tricky escape sequences' do
      [
        {
          input: '{"url": "http:\/\/example.com"}',
          expected_output: JSON.dump({ 'url' => 'http://example.com' }),
          desc: 'escaped forward slash (common in standard JSON)'
        },
        {
          input: '{"feed": "form\fbreak"}',
          expected_output: JSON.dump({ 'feed' => "form\fbreak" }),
          desc: 'escape \f kept as literal'
        },
        {
          input: '{"path": "C:\\Windows\\System32"}',
          expected_output: JSON.dump({ 'path' => 'C:\\Windows\\System32' }),
          desc: 'standard backslash escaping'
        },
        {
          input: '{"unicode": "val\u0075e"}',
          expected_output: JSON.dump({ 'unicode' => 'value' }),
          desc: 'valid unicode escape'
        },
        {
          input: '{"bad_uni": "val\u007e"}',
          expected_output: JSON.dump({ 'bad_uni' => "val\u007e" }),
          desc: 'incomplete/invalid unicode escape kept as literal'
        },
        {
          input: '{"bad_hex": "val\xZZ"}',
          expected_output: JSON.dump({ 'bad_hex' => 'val\\xZZ' }),
          desc: 'invalid hex escape \x kept as literal'
        }
      ].each do |tc|
        it "repairs #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when checking dangling array logic vs splitting' do
      [
        {
          input: '{"a": [1] [2]}',
          expected_output: JSON.dump({ 'a' => [1, 2] }),
          desc: 'merges dangling array inside the object (missing comma/brace)'
        },
        {
          input: '{"a": [1]} [2]',
          expected_output: JSON.dump([{ 'a' => [1] }, [2]]),
          desc: 'splits into list if brace is explicitly closed'
        },
        {
          input: '{"a": 1} [2]',
          expected_output: JSON.dump([{ 'a' => 1 }, [2]]),
          desc: 'splits into list if previous value was not an array'
        }
      ].each do |tc|
        it "repairs #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'with edge cases' do
      [
        {
          input: '1 ""',
          expected_output: '1',
          desc: 'multi-json with empty string skipped'
        },
        {
          input: "[1, # comment inside array \n 2]",
          expected_output: JSON.dump([1, 2]),
          desc: 'array with hash-style line comment'
        },
        {
          input: '[ "a", "b\"c" ]',
          expected_output: JSON.dump(['a', 'b"c']),
          desc: 'array with internal escaped quote logic'
        },
        {
          input: '{"a": "val\'ue"}',
          expected_output: JSON.dump({ 'a' => "val'ue" }),
          desc: 'string with escaped single quote'
        },
        {
          input: '{"key:colons": "value"}',
          expected_output: JSON.dump({ 'key:colons' => 'value' }),
          desc: 'key containing colon'
        },
        {
          input: '[ "key": "value", "key2": "value2" ]',
          expected_output: JSON.dump([{ 'key' => 'value', 'key2' => 'value2' }]),
          desc: 'implicit objects inside array without curly braces'
        },
        {
          input: '[ "key": "value", 123, "key2": "value2" ]',
          expected_output: JSON.dump([{ 'key' => 'value', 'key2' => 'value2' }]),
          desc: 'mixed implicit objects and literals in array'
        },
        {
          input: '{ ["complex", "key"]: "value" }',
          expected_output: JSON.dump({ 'complex' => 'value' }),
          desc: 'array used as an object key'
        },
        {
          input: '{ [1, 2]: "value" }',
          expected_output: JSON.dump({ '1' => 'value' }),
          desc: 'number array used as an object key'
        },
        {
          input: '{"a": 1} } ] garbage_text {"b": 2}',
          expected_output: JSON.dump({ 'b' => 2 }),
          desc: 'garbage and closing brackets between objects'
        },
        {
          input: '{"a": 1} .... {"b": 2}',
          expected_output: JSON.dump([{ 'a' => 1 }, '....', { 'b' => 2 }]),
          desc: 'dots/garbage between objects'
        },
        {
          input: '{"a": [1], "b": 2} [3]',
          expected_output: JSON.dump([{ 'a' => [1], 'b' => 2 }, [3]]),
          desc: 'does not merge dangling array if previous value is not an array'
        },
        {
          input: '{"a": [1], "b": [2]} [3]',
          expected_output: JSON.dump([{ 'a' => [1], 'b' => [2] }, [3]]),
          desc: 'merges dangling array into array'
        },
        {
          input: '{"a": [1]} [2, 3] [4]',
          expected_output: JSON.dump([{ 'a' => [1] }, [2, 3], [4]]),
          desc: 'chained dangling array merges'
        },
        {
          input: '{""key"": "value", "key2": ""value2""}',
          expected_output: JSON.dump({ 'key' => 'value', 'key2' => 'value2' }),
          desc: 'mixed doubled and normal quotes'
        },
        {
          input: '{ ""key": "value" }',
          expected_output: JSON.dump({ 'key' => 'value' }),
          desc: 'asymmetric doubled quotes on key start'
        },
        {
          input: '{"a": 1.23E+5, "b": 1.23e-2}',
          expected_output: JSON.dump({ 'a' => 123_000.0, 'b' => 0.0123 }),
          desc: 'valid scientific notation with E and e'
        },
        {
          input: '{"a": 123., "b": .456}',
          expected_output: JSON.dump({ 'a' => 123.0, 'b' => 0.456 }),
          desc: 'numbers with trailing or leading dots'
        },
        {
          input: '{"a": 00123}',
          expected_output: JSON.dump({ 'a' => 123 }),
          desc: 'leading zeros'
        },
        {
          input: '{"key"/*comment*/: "value"}',
          expected_output: JSON.dump({ 'key' => 'value' }),
          desc: 'block comment between key and colon'
        },
        {
          input: '{"key": "value"//comment\n, "next": 1}',
          expected_output: JSON.dump({ 'key' => 'value', 'next' => 1 }),
          desc: 'line comment replacing comma'
        },
        {
          input: '{"a": "line\nfeed", "b": "back\bspace", "c": "form\ffeed", "d": "tab\tchar"}',
          expected_output: JSON.dump({ 'a' => "line\nfeed", 'b' => "back\bspace", 'c' => "form\ffeed",
                                       'd' => "tab\tchar" }),
          desc: 'standard JSON escape sequences'
        },
        {
          input: '{"a": {"b": {"c": [1, 2',
          expected_output: JSON.dump({ 'a' => { 'b' => { 'c' => [1, 2] } } }),
          desc: 'deeply nested unclosed objects and arrays'
        },
        {
          input: '{key-dash: "value", key_underscore: "value", key$dollar: "value"}',
          expected_output: JSON.dump({ 'key-dash' => 'value', 'key_underscore' => 'value', 'key$dollar' => 'value' }),
          desc: 'unquoted keys with special allowed characters'
        }
      ].each do |test_case|
        it "repairs #{test_case[:desc]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided ambiguous number formats' do
      [
        {
          input: '{"thousands": 1,234}',
          expected_output: JSON.dump({ thousands: 1.234 })
        },
        {
          input: '{"multi_comma": 1,234,567}',
          expected_output: JSON.dump({ multi_comma: '1,234,567' })
        },
        {
          input: '{"trailing_minus": 123-}',
          expected_output: JSON.dump({ trailing_minus: 123 })
        },
        {
          input: '{"underscores": 1_000}',
          expected_output: JSON.dump({ underscores: 1000 })
        }
      ].each do |test_case|
        it "repairs number format #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided tricky unicode and escapes' do
      [
        {
          input: '{"short_unicode": "\\u12"}',
          expected_output: JSON.dump({ short_unicode: '\\u12' })
        },
        {
          input: '{"broken_escape": "val\\"}',
          expected_output: JSON.dump({ broken_escape: 'val"' })
        },
        {
          input: '{"hex_escape": "\\x41"}',
          expected_output: JSON.dump({ hex_escape: 'A' })
        }
      ].each do |test_case|
        it "handles escapes in #{test_case[:input]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when merging dangling arrays with interference' do
      [
        {
          input: '{"a": [1] /* comment */ [2]}',
          expected_output: JSON.dump({ 'a' => [1, 2] }),
          desc: 'dangling array merge with intervening block comment'
        },
        {
          input: "{\"a\": [1] // comment \n [2]}",
          expected_output: JSON.dump({ 'a' => [1, 2] }),
          desc: 'dangling array merge with intervening line comment'
        },
        {
          input: '{"a": [1], "b": [3] [4]}',
          expected_output: JSON.dump({ 'a' => [1], 'b' => [3, 4] }),
          desc: 'dangling array on second key'
        }
      ].each do |tc|
        it "repairs #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when provided unbalanced or garbage inputs' do
      [
        {
          input: ']]]]]]',
          expected_output: ''
        },
        {
          input: '{{{{{{',
          expected_output: JSON.dump({})
        },
        {
          input: 'random garbage text',
          expected_output: ''
        },
        {
          input: '{"key": "value"} random garbage',
          expected_output: JSON.dump({ key: 'value' })
        }
      ].each do |test_case|
        it "robustly handles garbage: #{test_case[:input]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when provided deeply nested or repeated empty structures' do
      [
        {
          input: '{{}}',
          expected_output: JSON.dump({})
        },
        {
          input: '{{{{"a": 1}}}}',
          expected_output: JSON.dump({ 'a' => 1 })
        },
        {
          input: '[[[]]]',
          expected_output: JSON.dump([[[]]])
        },
        {
          input: '{}{}{}',
          # Explanation: The parser collapses consecutive top-level objects
          expected_output: JSON.dump({})
        },
        {
          input: '[{}, {}, {}]',
          # Explanation: Inside an array, objects are preserved as elements
          expected_output: JSON.dump([{}, {}, {}])
        },
        {
          input: '{{ "a": 1 } { "b": 2 }}',
          # Explanation: effectively parses as { "a": 1 }, then { "b": 2 }.
          # Top level logic keeps the last object.
          expected_output: JSON.dump({ 'b' => 2 })
        },
        {
          input: '[[[[1]]]]',
          expected_output: JSON.dump([[[[1]]]])
        }
      ].each do |test_case|
        it "repairs #{test_case[:input]} to #{test_case[:expected_output]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end

    context 'when fast-path for unquoted keys' do
      [
        {
          input: '{ simple: "val" }',
          expected_output: JSON.dump({ 'simple' => 'val' }),
          desc: 'simple alphabetic unquoted key'
        },
        {
          input: '{ my_var_name: "val" }',
          expected_output: JSON.dump({ 'my_var_name' => 'val' }),
          desc: 'underscored identifier'
        },
        {
          input: '{ $special-var_1: "val" }',
          expected_output: JSON.dump({ '$special-var_1' => 'val' }),
          desc: 'special characters ($, -) allowed in fast-path regex'
        },
        {
          input: '{ key1: "v1", key2: "v2", key3: "v3" }',
          expected_output: JSON.dump({ 'key1' => 'v1', 'key2' => 'v2', 'key3' => 'v3' }),
          desc: 'sequence of fast-path keys'
        },
        {
          input: '{veryLongVariableNameThatShouldBeScannedInOneGo: true}',
          expected_output: JSON.dump({ 'veryLongVariableNameThatShouldBeScannedInOneGo' => true }),
          desc: 'long key triggering chunk scan'
        },
        {
          input: '{ key:val }',
          expected_output: JSON.dump({ 'key' => 'val' }),
          desc: 'unquoted key and unquoted value'
        }
      ].each do |tc|
        it "correctly parses #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when parse_number optimization and rewind logic' do
      [
        {
          input: '{"a":1,"b":2}',
          expected_output: JSON.dump({ 'a' => 1, 'b' => 2 }),
          desc: 'compact JSON with comma immediately following number'
        },
        {
          input: '{"a":123,"b":456}',
          expected_output: JSON.dump({ 'a' => 123, 'b' => 456 }),
          desc: 'compact JSON with multi-digit numbers'
        },
        {
          input: '{"float":1.5,"int":1}',
          expected_output: JSON.dump({ 'float' => 1.5, 'int' => 1 }),
          desc: 'compact JSON with mixed number types'
        },
        {
          input: '[1,2,3,4]',
          expected_output: JSON.dump([1, 2, 3, 4]),
          desc: 'compact array with numbers'
        },
        {
          input: '{"a": 1, "b": 2}',
          expected_output: JSON.dump({ 'a' => 1, 'b' => 2 }),
          desc: 'standard spacing (boundary check)'
        },
        {
          input: '{"key": 1e5,}',
          expected_output: JSON.dump({ 'key' => 100_000.0 }),
          desc: 'scientific notation followed by comma'
        },
        {
          input: '{"key": 123-}',
          expected_output: JSON.dump({ 'key' => 123 }),
          desc: 'number with invalid trailer needing strip and rewind'
        }
      ].each do |tc|
        it "correctly handles #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'when peek_char unicode stability' do
      [
        {
          input: '{"ascii": 1, "uni\u00f6": 2}',
          expected_output: JSON.dump({ 'ascii' => 1, 'uniö' => 2 }),
          desc: 'mixed ASCII and Unicode escape'
        },
        {
          input: '{"👍": "thumbs_up"}',
          expected_output: JSON.dump({ '👍' => 'thumbs_up' }),
          desc: 'multibyte emoji as key'
        },
        {
          input: '{"“smart”": "quotes"}',
          expected_output: JSON.dump({ '“smart”' => 'quotes' }),
          desc: 'multibyte smart quotes as key'
        },
        {
          input: '{"key": "value with — dash"}',
          expected_output: JSON.dump({ 'key' => 'value with — dash' }),
          desc: 'multibyte char in value'
        },
        {
          input: '{"Український": "text"}',
          expected_output: JSON.dump({ 'Український' => 'text' }),
          desc: 'Cyrillic characters'
        }
      ].each do |tc|
        it "correctly parses #{tc[:desc]}" do
          expect(described_class.repair(tc[:input])).to eq(tc[:expected_output])
        end
      end
    end

    context 'with valid JSON (direct parser usage)' do
      [
        {
          input: '{"a": 1}',
          expected_output: JSON.dump({ 'a' => 1 })
        },
        {
          input: '[1, 2, 3]',
          expected_output: JSON.dump([1, 2, 3])
        },
        {
          input: '{"a": [1, 2], "b": {"c": 3}}',
          expected_output: JSON.dump({ 'a' => [1, 2], 'b' => { 'c' => 3 } })
        },
        {
          input: '{"simple": "string", "number": 123, "bool": true, "nil": null}',
          expected_output: JSON.dump({ simple: 'string', number: 123, bool: true, nil: nil })
        },
        {
          input: '{"nested": {"array": [1, 2, {"deep": "obj"}]}}',
          expected_output: JSON.dump({ nested: { array: [1, 2, { deep: 'obj' }] } })
        },
        {
          input: '{"unicode": "こんにちは", "emoji": "👍"}',
          expected_output: JSON.dump({ unicode: 'こんにちは', emoji: '👍' })
        },
        {
          input: '{"escapes":"\" \\\\ / \\b \\f \\n \\r \\t"}',
          expected_output: JSON.dump({ escapes: "\" \\ / \b \f \n \r \t" })
        },
        {
          input: '{"empty_obj": {}, "empty_arr": []}',
          expected_output: JSON.dump({ empty_obj: {}, empty_arr: [] })
        }
      ].each do |test_case|
        it "parses valid JSON #{test_case[:input]}" do
          expect(described_class.repair(test_case[:input])).to eq(test_case[:expected_output])
        end
      end
    end
  end
end
