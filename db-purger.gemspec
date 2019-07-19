# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'db-purger'
  s.version     = '0.1.3'
  s.licenses    = ['MIT']
  s.summary     = 'DB Purger by top level id'
  s.description = 'Purge database tables by top level id in batches'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/db-purger'
  s.files       = Dir.glob('lib/**/*.rb')

  s.add_runtime_dependency 'dynamic-active-model'
  s.add_runtime_dependency 'inheritance-helper'
end
