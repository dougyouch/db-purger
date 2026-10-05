# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'db-purger'
  s.version     = '0.7.0'
  s.licenses    = ['MIT']
  s.summary     = 'Purge all data tied to a top-level id across related tables, in batches'
  s.description = 'DB Purger deletes (or soft-deletes) every row related to a single top-level record ' \
                  '(e.g. a company or account) using a declarative Ruby purge plan. Tables are purged in ' \
                  'primary-key batches, child tables before their parents, with plan validation against the ' \
                  'live schema, an explain (dry-run) mode that emits SQL, and ActiveSupport::Notifications ' \
                  'instrumentation for metrics.'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/db-purger'
  s.files       = Dir.glob('lib/**/*.rb') + %w[README.md ARCHITECTURE.md LICENSE.txt]
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 3.2'

  s.metadata = {
    'source_code_uri' => s.homepage,
    'bug_tracker_uri' => "#{s.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  s.add_dependency 'activerecord', '>= 7.0'
  s.add_dependency 'dynamic-active-model', '>= 0.9.1', '< 2'
end
