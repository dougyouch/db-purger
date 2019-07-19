# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTableHelper keeps track of common code between purgers
  module PurgeTableHelper
    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    private

    def purge_nested_tables(batch)
      purge_child_tables(batch) unless @table.nested_plan.child_tables.empty?
      purge_parent_tables
    end

    def purge_child_tables(batch)
      ids = batch_values(batch, model.primary_key)

      @table.nested_plan.child_tables.each do |table|
        next if table.foreign_key

        PurgeTable.new(@database, table, table.field, ids).purge!
      end
    end

    def purge_parent_tables
      @table.nested_plan.parent_tables.each do |table|
        PurgeTable.new(@database, table, table.field, @purge_value).purge!
      end
    end

    def purge_foreign_tables(batch)
      @table.nested_plan.child_tables.each do |table|
        next unless table.foreign_key
        next if (purge_values = batch_values(batch, table.foreign_key)).empty?

        PurgeTable.new(@database, table, table.field, purge_values).purge!
      end
    end

    def batch_values(batch, field)
      batch.map { |record| record.send(field) }.compact
    end

    def foreign_tables?
      @table.nested_plan.child_tables.any?(&:foreign_key)
    end

    def delete_records_with_instrumentation(scope, num_records = nil)
      @num_deleted ||= 0
      ActiveSupport::Notifications.instrument('delete_records.db_purger',
                                              table_name: @table.name,
                                              num_records: num_records) do |payload|
        records_deleted =
          if ::DBPurger.config.explain?
            delete_sql = scope.to_sql.sub(/SELECT .*?FROM/, 'DELETE FROM')
            ::DBPurger.config.explain_file.puts(delete_sql)
            scope.count
          elsif @table.mark_deleted_field
            scope.update_all(@table.mark_deleted_field => @table.mark_deleted_value)
          else
            scope.delete_all
          end
        @num_deleted += records_deleted
        payload[:records_deleted] = records_deleted
        payload[:deleted] = @num_deleted
      end
    end

    def delete_records(batch)
      if foreign_tables?
        delete_records_and_foreign_tables(batch)
      else
        delete_records_by_primary_key(batch)
      end
    end

    def delete_records_and_foreign_tables(batch)
      model.transaction do
        delete_records_by_primary_key(batch)
        purge_foreign_tables(batch)
      end
    end

    def delete_records_by_primary_key(batch)
      ids = batch_values(batch, model.primary_key)
      scope = model.where(model.primary_key => ids)
      delete_records_with_instrumentation(scope, ids.size)
    end

    def purge_search_tables
      @table.nested_plan.search_tables.each do |table|
        PurgeTableScanner.new(@database, table).purge!
      end
    end
  end
end
