# frozen_string_literal: true

require 'rubygems'
require 'bundler'
require 'securerandom'
require 'active_record'

begin
  Bundler.require(:default, :spec)
rescue Bundler::BundlerError => e
  warn e.message
  warn 'Run `bundle install` to install missing gems'
  exit e.status_code
end

$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
$LOAD_PATH.unshift(__dir__)
require 'db-purger'

require 'support/test_db'

# ActiveRecord::Base.logger = Logger.new(STDOUT)

require 'factories/test_factory'
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
