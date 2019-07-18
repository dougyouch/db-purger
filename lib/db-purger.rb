# frozen_string_literal: true

# DBPurger is a tool to delete data from tables based on a initial purge value
module DBPurger
  autoload :PurgeTable, 'db-purger/purge_table'
  autoload :PurgeTableHelper, 'db-purger/purge_table_helper'
  autoload :PurgeTableScanner, 'db-purger/purge_table_scanner'
  autoload :Schema, 'db-purger/schema'
  autoload :SchemaBuilder, 'db-purger/schema_builder'
  autoload :SchemaValidator, 'db-purger/schema_validator'
  autoload :Table, 'db-purger/table'
end
