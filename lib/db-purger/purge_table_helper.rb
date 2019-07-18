# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTableHelper keeps track of common code between purgers
  module PurgeTableHelper
    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    private

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

    def purge_search_tables
      @table.nested_schema.search_tables.each do |table|
        PurgeTableScanner.new(@database, table).purge!
      end
    end
  end
end
