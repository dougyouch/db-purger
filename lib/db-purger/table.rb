module DBPurger
  class Table
    DEFAULT_BATCH_SIZE = 10_000

    attr_reader :name,
                :parent_field,
                :child_field,
                :batch_size

    def initialize(name, parent_field, child_field, batch_size = nil)
      @name = name
      @parent_field = parent_field
      @child_field = child_field
      @batch_size = batch_size || DEFAULT_BATCH_SIZE
    end

    def nested_schema
      @nested_schema ||= Schema.new
    end

    def nested_tables?
      @nested_schema != nil
    end

    def table_names
      if @nested_schema
        [@name] + @nested_schema.table_names
      else
        [@name]
      end
    end
  end
end
