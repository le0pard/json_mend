# frozen_string_literal: true

# gem install benchmark-ips json-repair json_mend
# ruby -Ilib benchmark_comparison.rb
require 'benchmark/ips'
require 'json'

# --- Load Libraries ---
begin
  require 'json_mend'
rescue LoadError
  abort "❌ Could not load 'json_mend'. Make sure you are in the gem root or have it installed."
end

begin
  require 'json/repair'
rescue LoadError
  puts "❌ Could not load 'json-repair'. Benchmarks for it will be skipped."
end

puts '========================================================='
puts '  🚀 JSON Repair Benchmark (IPS) '
puts "     JsonMend (v#{JsonMend::VERSION}) vs json-repair-rb (v#{JSON::Repair::VERSION})"
puts '========================================================='
puts

# --- Test Data ---

json_object = '{"id": 1, "name": "Test", "active": true, "tags": ["a", "b"]}'

TEST_CASES = {
  valid_single: {
    label: 'Valid Single JSON',
    input: json_object
  },
  return_objects: {
    label: 'Valid JSON (Return Ruby Objects)',
    input: json_object,
    return_objects: true
  },
  generator_error: {
    label: 'Valid Syntax but Invalid UTF-8 (GeneratorError)',
    input: "{\"status\": \"ok\", \"data\": \"bad\xFFbyte\"}",
    return_objects: true
  },
  concatenated: {
    label: 'Concatenated JSON (x10)',
    input: json_object * 10
  },
  simple_fix: {
    label: 'Simple Fix (Missing Quotes)',
    input: '{name: "Alice", age: 30, city: "Wonderland"}'
  },
  trailing_comma: {
    label: 'Trailing Commas',
    input: '{"items": [1, 2, 3,], "active": true,}'
  },
  comments: {
    label: 'Comments (// and #)',
    input: <<~JSON
      {
        "key": "value", // This is a comment
        "config": {
          "timeout": 100 # Another comment
        }
      }
    JSON
  },
  complex: {
    label: 'Complex & Mixed Errors',
    input: <<~JSON
      {
        name: "Broken",
        "nested": [
          {id: 1,},
          {id: 2}
        ],
        "dangling": [1, 2, 3
    JSON
  },
  garbage: {
    label: 'Heavy Garbage / Hallucinations',
    input: 'Here is the JSON: ```json {"a": 1} ``` and some other text.'
  },
  python_style: {
    label: 'Python Literals (True/None)',
    input: '{"is_valid": True, "missing": None, "wrong_bool": False}'
  },
  single_quotes: {
    label: 'Single Quotes (JS Style)',
    input: "{'id': 123, 'status': 'pending', 'meta': {'active': true}}"
  },
  deep_nesting: {
    label: 'Deeply Nested (Stack Test)',
    input: "#{'{"a":' * 50}1#{'}' * 50}"
  },
  unbalanced: {
    label: 'Truncated / Unbalanced',
    input: '{"users": [{"id": 1, "name": "Alice"}, {"id": 2'
  },
  unescaped_control: {
    label: 'Unescaped Newlines/Tabs',
    input: "{\"bio\": \"This is a \n multi-line string \t with tabs.\"}"
  },
  large_array: {
    label: 'Large Single Array (Throughput)',
    input: "[#{(1..1000).map { |i| %({"id": #{i}, "val": "item_#{i}"}) }.join(',')}]"
  },
  concatenated_complex: {
    label: 'Concatenated + Broken (LLM Stream)',
    input: '{"part": 1} {part: 2, "broken": true} {"part": 3}'
  }
}.freeze

# Helper to check if a library supports the input before benchmarking
def supported?(library_proc, input)
  library_proc.call(input)
  true
rescue StandardError
  false
end

# --- Run Benchmarks ---

TEST_CASES.each_value do |data|
  puts "\n\n🔸 Scenario: #{data[:label]}"
  puts '-' * 40

  # Check if this specific test requires returning objects instead of a string
  return_objs = data.fetch(:return_objects, false)

  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1) # Short duration for quick checks

    # 1. JsonMend
    mend_proc = ->(i) { JsonMend.repair(i, return_objects: return_objs) }

    if supported?(mend_proc, data[:input])
      x.report('JsonMend') do
        JsonMend.repair(data[:input], return_objects: return_objs)
      end
    else
      puts '   JsonMend: ❌ Not Supported'
    end

    # 2. json-repair
    if defined?(JSON::Repair)
      # For a fair comparison, if return_objects is true, json-repair must also parse its own output
      repair_proc = ->(i) { return_objs ? JSON.parse(JSON.repair(i)) : JSON.repair(i) }

      if supported?(repair_proc, data[:input])
        x.report('json-repair') do
          return_objs ? JSON.parse(JSON.repair(data[:input])) : JSON.repair(data[:input])
        end
      else
        puts '   json-repair: ❌ Not Supported'
      end
    end

    x.compare!
  end
end
