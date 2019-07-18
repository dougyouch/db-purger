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
        if model.primary_key
          purge_in_batches!
        else
          purge_all!
        end
        purge_search_tables
        payload[:num_deleted] = @num_deleted
      end
    end

    private

    def purge_all!
      scope = model.where(@purge_field => @purge_value)
      scope = scope.where(@table.conditions) if @table.conditions
      ActiveSupport::Notifications.instrument('delete_all.db_purger',
                                              table_name: @table.name) do |payload|
        payload[:num_deleted] = scope.delete_all
        @num_deleted += payload[:num_deleted]
      end
    end

    def purge_in_batches!
      start_id = nil
      until (batch = next_batch(start_id)).empty?
        start_id = batch.last.send(model.primary_key)
        purge_nested_tables(batch) if @table.nested_tables?
        delete_records(batch)
      end
    end

    # rubocop:disable Metrics/AbcSize
    def next_batch(start_id)
      scope = model
              .select([model.primary_key] + @table.foreign_keys)
              .where(@purge_field => @purge_value)
              .order(model.primary_key).limit(@table.batch_size)
      scope = scope.where(@table.conditions) if @table.conditions
      scope = scope.where("#{model.primary_key} > #{model.connection.quote(start_id)}") if start_id
      ActiveSupport::Notifications.instrument('next_batch.db_purger',
                                              table_name: @table.name) do |payload|
        records = scope.to_a
        payload[:num_records] = records.size
        records
      end
    end
    # rubocop:enable Metrics/AbcSize
  end
end
