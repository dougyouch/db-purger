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

DB_FILE = 'spec/test.db'
DB_CONFIG = {
  adapter: 'sqlite3',
  database: DB_FILE
}.freeze
File.unlink(DB_FILE) if File.exist?(DB_FILE)
ActiveRecord::Base.establish_connection(DB_CONFIG)
ActiveRecord::Schema.verbose = false
require 'support/db/schema'

TestDB =  Module.new
DYNAMIC_DATABASE = DynamicActiveModel::Database.new(TestDB, DB_CONFIG)
DYNAMIC_DATABASE.create_models!

require 'factories/test_factory'
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
