# frozen_string_literal: true

require 'fileutils'

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
DYNAMIC_DATABASE.skip_table('ar_internal_metadata')
DYNAMIC_DATABASE.skip_table('schema_migrations')
DYNAMIC_DATABASE.skip_table('tmp_load_data_table')
DYNAMIC_DATABASE.create_models!

DynamicActiveModel::Associations.new(DYNAMIC_DATABASE).tap do |assoc|
  assoc.add_foreign_key('websites', 'company_website_id', 'company_website')
  assoc.build!
end

def reset_test_database
  FileUtils.cp(DB_FILE_BAK, DB_FILE)
end

class TestDB::Company
  self.ignored_columns += ['hash']
end

class TestDB::Event
  belongs_to :model, polymorphic: true
end
