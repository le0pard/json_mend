# frozen_string_literal: true

require 'rbs'
require 'rbs/test'

# sig/json_mend.rbs must be valid and cover exactly the public JsonMend API.
RSpec.describe JsonMend do
  describe 'sig/json_mend.rbs' do
    let(:environment) do
      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(File.expand_path('../sig', __dir__)))
      %w[json strscan].each { |library| loader.add(library:, version: nil) }
      RBS::Environment.from_loader(loader).resolve_type_names
    end
    let(:builder) { RBS::DefinitionBuilder.new(env: environment) }
    let(:singleton) { builder.build_singleton(type_name('JsonMend')) }

    def type_name(name)
      RBS::TypeName.parse("::#{name}")
    end

    def own_methods(definition, name)
      definition.methods.select { |_, method| method.defined_in.to_s == "::#{name}" }.keys
    end

    it 'builds every declared type', :aggregate_failures do
      expect { builder.build_instance(type_name('JsonMend')) }.not_to raise_error
      expect { builder.build_singleton(type_name('JsonMend')) }.not_to raise_error
      expect { builder.expand_alias(type_name('JsonMend::json_value')) }.not_to raise_error
    end

    it 'declares every public JsonMend method' do
      expect(own_methods(singleton, 'JsonMend')).to match_array(described_class.singleton_methods(false))
    end

    it 'declares the version constant' do
      expect(environment.constant_decls).to have_key(type_name('JsonMend::VERSION'))
    end

    describe '.repair' do
      let(:return_type) { singleton.methods[:repair].method_types.first.type.return_type }
      let(:checker) do
        RBS::Test::TypeCheck.new(
          self_class: described_class.singleton_class, builder:, sample_size: 100, unchecked_classes: []
        )
      end

      [
        '{"a": [1, 2.5, true, null], "b": {"c": "d"}}',
        '{a: b, "c": [1, 2',
        "['x', 1e3, falsy",
        'not json at all',
        ''
      ].product([false, true]).each do |input, return_objects|
        it "matches the signature for #{input.inspect} with return_objects: #{return_objects}" do
          expect(checker.value(described_class.repair(input, return_objects:), return_type)).to be(true)
        end
      end
    end
  end
end
