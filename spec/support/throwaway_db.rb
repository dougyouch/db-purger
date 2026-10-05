# frozen_string_literal: true

require 'sqlite3'

# Builds a standalone SQLite database from raw SQL and loads it through dynamic-active-model, with
# associations built, so specs can exercise schemas the shared TestDB doesn't have.
module ThrowawayDB
  # base_module must be named: has_and_belongs_to_many interpolates the model class names into code
  def self.create(name, base_module, statements)
    db_file = "spec/#{name}.db"
    File.unlink(db_file) if File.exist?(db_file)
    SQLite3::Database.new(db_file).tap do |db|
      statements.each { |sql| db.execute(sql) }
      db.close
    end

    database = DynamicActiveModel::Database.new(base_module, { adapter: 'sqlite3', database: db_file })
    database.create_models!
    DynamicActiveModel::Associations.new(database).build!
    database
  end

  # empties every table; foreign keys are suspended so the delete order doesn't matter
  def self.clean(database)
    connection = database.models.first.connection
    connection.execute('PRAGMA foreign_keys = OFF')
    database.models.each(&:delete_all)
  ensure
    connection&.execute('PRAGMA foreign_keys = ON')
  end

  def self.destroy(name, database)
    database.models.first&.connection_pool&.disconnect!
    File.unlink("spec/#{name}.db") if File.exist?("spec/#{name}.db")
  end
end
