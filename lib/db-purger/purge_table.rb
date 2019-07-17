# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTable is used to delete table from tables in batches if possible
  class PurgeTable
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

    def purge_nested_tables(batch)
      purge_child_tables(batch) unless @table.nested_schema.child_tables.empty?
      purge_parent_tables
    end

    def purge_child_tables(batch)
      ids = batch_values(batch, model.primary_key)

      @table.nested_schema.child_tables.each do |table|
        next if table.foreign_key

        PurgeTable.new(@database, table, table.field, ids).purge!
      end
    end

    def purge_parent_tables
      @table.nested_schema.parent_tables.each do |table|
        PurgeTable.new(@database, table, table.field, @purge_value).purge!
      end
    end

    def purge_foreign_tables(batch)
      @table.nested_schema.child_tables.each do |table|
        next unless table.foreign_key
        next if (purge_values = batch_values(batch, table.foreign_key)).empty?

        PurgeTable.new(@database, table, table.field, purge_values).purge!
      end
    end

    def batch_values(batch, field)
      batch.map { |record| record.send(field) }.compact
    end

    def foreign_tables?
      @table.nested_schema.child_tables.any?(&:foreign_key)
    end

    def delete_records_with_instrumentation(ids)
      ActiveSupport::Notifications.instrument('delete_records.db_purger',
                                              table_name: @table.name,
                                              num_records: ids.size) do |payload|
        payload[:num_deleted] = model.where(model.primary_key => ids).delete_all
        @num_deleted += payload[:num_deleted]
      end
    end

    def delete_records(batch)
      if foreign_tables?
        delete_records_and_foreign_tables(batch)
      else
        delete_records_with_instrumentation(batch_values(batch, model.primary_key))
      end
    end

    def delete_records_and_foreign_tables(batch)
      model.transaction do
        delete_records_with_instrumentation(batch_values(batch, model.primary_key))
        purge_foreign_tables(batch)
      end
    end
  end
end
