# frozen_string_literal: true

require 'rubygems'
require 'bundler'
require 'securerandom'
require 'active_record'
require 'fileutils'

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
DB_FILE_BAK = 'spec/test.db.bak'
DB_CONFIG = {
  adapter: 'sqlite3',
  database: DB_FILE
}.freeze
File.unlink(DB_FILE) if File.exist?(DB_FILE)
File.unlink(DB_FILE_BAK) if File.exist?(DB_FILE_BAK)
ActiveRecord::Base.establish_connection(DB_CONFIG)
ActiveRecord::Schema.verbose = false
require 'support/db/schema'
FileUtils.cp(DB_FILE, DB_FILE_BAK)

TestDB = Module.new
DYNAMIC_DATABASE = DynamicActiveModel::Database.new(TestDB, DB_CONFIG)
DYNAMIC_DATABASE.skip_table('tmp_load_data_table')
DYNAMIC_DATABASE.create_models!
DynamicActiveModel::Associations.new(DYNAMIC_DATABASE).build!

def reset_test_database
  FileUtils.cp(DB_FILE_BAK, DB_FILE)
end

# ActiveRecord::Base.logger = Logger.new(STDOUT)

require 'factories/test_factory'
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
