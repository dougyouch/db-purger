# frozen_string_literal: true

# DBPurger is a tool to delete data from tables based on a initial purge value
module DBPurger
  autoload :PurgeTable, 'db-purger/purge_table'
  autoload :Schema, 'db-purger/schema'
  autoload :SchemaBuilder, 'db-purger/schema_builder'
  autoload :Table, 'db-purger/table'
end
