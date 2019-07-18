# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTableScanner scans the entire table in batches use the search_proc to determine what ids to delete
  class PurgeTableScanner
    include PurgeTableHelper

    def initialize(database, table)
      @database = database
      @table = table
    end

    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    def purge!
      ActiveSupport::Notifications.instrument('purge.db_purger',
                                              table_name: @table.name) do |payload|
        purge_in_batches!
        purge_search_tables
        payload[:deleted] = @num_deleted
      end
    end

    private

    def purge_in_batches!
      scope = model
      scope = scope.where(@table.conditions) if @table.conditions
      scope.find_in_batches(batch_size: @table.batch_size) do |batch|
        unless (batch = @table.search_proc.call(batch)).empty?
          purge_nested_tables(batch) if @table.nested_tables?
          delete_records(batch)
        end
      end
    end
  end
end
