module DBPurger
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
      model.where(@purge_field => @purge_value).delete_all
    end

    def purge_in_batches!
      start_id = nil
      while !(batch = next_batch(start_id)).empty?
        start_id = batch.last
        purge_nested_tables(batch) if @table.nested_tables?
        model.where(model.primary_key => batch).delete_all
      end
    end

    def next_batch(start_id)
      scope = model
                .select(model.primary_key)
                .where(@purge_field => @purge_value)
                .order(model.primary_key).limit(@table.batch_size)
      scope = scope.where("#{model.primary_key} > #{model.connection.quote(start_id)}") if start_id
      scope.map { |record| record.send(model.primary_key) }
    end

    def purge_nested_tables(batch)
      @table.nested_schema.child_tables.each do |table|
        PurgeTable.new(@database, table, table.child_field, batch).purge!
      end
      @table.nested_schema.parent_tables.each do |table|
        PurgeTable.new(@database, table, table.parent_field, batch).purge!
      end
    end
  end
end
