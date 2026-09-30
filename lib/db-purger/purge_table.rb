# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTable is used to delete table from tables in batches if possible
  class PurgeTable
    include PurgeTableHelper

    def initialize(database, table, purge_field, purge_value)
      @database = database
      @table = table
      @purge_field = purge_field
      @purge_value = purge_value
      @num_deleted = 0
    end

    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    def purge!
      ActiveSupport::Notifications.instrument('purge.db_purger',
                                              table_name: @table.name,
                                              purge_field: @purge_field) do |payload|
        payload[:deleted] = @num_deleted
        if model.primary_key
          purge_in_batches!
        else
          ensure_no_nested_key_tables!
          purge_all!
        end
        purge_search_tables
        payload[:deleted] = @num_deleted
      end
      @num_deleted
    end

    private

    # without a primary key there are no batch ids to propagate, so nested tables would be silently skipped
    def ensure_no_nested_key_tables!
      return unless @table.nested_key_tables?

      raise("#{@table.name} has no primary key and cannot have nested child or parent tables")
    end

    def purge_all!
      scope = model.where(@purge_field => @purge_value)
      scope = scope.where(@table.conditions) if @table.conditions
      delete_records_with_instrumentation(scope)
    end

    def purge_in_batches!
      unless @table.parent_tables?
        each_batch do |batch|
          purge_nested_tables(batch) if @table.nested_tables?
          delete_records(batch)
        end
        return
      end

      # Parent tables may reference this table's rows and be referenced by its child tables,
      # so purge them after the children but before this table's rows.
      each_batch { |batch| purge_nested_tables(batch) }
      purge_parent_tables
      each_batch { |batch| delete_records(batch) }
    end

    def each_batch
      start_id = nil
      until (batch = next_batch(start_id)).empty?
        start_id = batch.last[model.primary_key]
        yield batch
      end
    end

    def next_batch(start_id)
      ActiveSupport::Notifications.instrument('next_batch.db_purger',
                                              table_name: @table.name,
                                              start_id: start_id) do |payload|
        records = batch_scope(start_id).to_a
        payload[:num_records] = records.size
        records
      end
    end

    # rubocop:disable Metrics/AbcSize
    def batch_scope(start_id)
      scope = model
              .select([model.primary_key] + @table.foreign_keys)
              .where(@purge_field => @purge_value)
              .order(model.primary_key)
              .limit(@table.batch_size)
      scope = scope.where(@table.conditions) if @table.conditions
      scope = scope.where("#{model.primary_key} > #{model.connection.quote(start_id)}") if start_id
      scope
    end
    # rubocop:enable Metrics/AbcSize
  end
end
