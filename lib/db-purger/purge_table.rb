# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTable is used to delete table from tables in batches if possible
  class PurgeTable
    def initialize(database, table, purge_field, purge_value)
      @database = database
      @table = table
      @purge_field = purge_field
      @purge_value = purge_value
    end

    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    def purge!
      if model.primary_key
        purge_in_batches!
      else
        purge_all!
      end
    end

    private

    def purge_all!
      scope = model.where(@purge_field => @purge_value)
      scope = scope.where(@table.conditions) if @table.conditions
      scope.delete_all
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
      scope.to_a
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

    def delete_records(batch)
      if foreign_tables?
        delete_records_and_foreign_tables(batch)
      else
        model.where(model.primary_key => batch_values(batch, model.primary_key)).delete_all
      end
    end

    def delete_records_and_foreign_tables(batch)
      model.transaction do
        model.where(model.primary_key => batch_values(batch, model.primary_key)).delete_all
        purge_foreign_tables(batch)
      end
    end
  end
end
