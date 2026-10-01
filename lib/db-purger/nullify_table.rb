# frozen_string_literal: true

module DBPurger
  # DBPurger::NullifyTable clears a nullable column that points at a batch of rows about to be deleted,
  # the purge-time equivalent of ON DELETE SET NULL. It updates the referencing rows instead of deleting them.
  class NullifyTable
    include PurgeTableHelper

    def initialize(database, table, purge_values)
      @database = database
      @table = table
      @purge_values = purge_values
    end

    def nullify!
      ActiveSupport::Notifications.instrument('nullify_records.db_purger',
                                              table_name: @table.name,
                                              nullify_field: @table.field,
                                              num_records: @purge_values.size) do |payload|
        payload[:records_nullified] = ::DBPurger.config.explain? ? explain_nullify : nullify_records
      end
    end

    private

    def nullify_records
      scope.update_all(@table.field => nil)
    end

    def scope
      scope = model.where(@table.field => @purge_values)
      scope = scope.where(@table.conditions) if @table.conditions
      scope
    end

    def explain_nullify
      ::DBPurger.config.explain_file.puts("#{explain_update_sql(scope, field_quoted, 'NULL')};")
      scope.count
    end

    def field_quoted
      model.connection.quote_column_name(@table.field)
    end
  end
end
