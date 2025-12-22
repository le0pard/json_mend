# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc 'Validate RBS files'
task :rbs_validate do
  sh 'bundle exec rbs -I sig -r json -r strscan validate'
end

task default: %i[rbs_validate rubocop spec]
