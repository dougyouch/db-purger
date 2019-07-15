module DBPurger
  class SchemaBuilder
    def initialize(schema)
      @schema = schema
    end

    def top_table(table_name, parent_field, &block)
      @schema.top_table = create_table(table_name, parent_field, nil, &block)
    end

    def parent_table(table_name, parent_field, &block)
      table = create_table(table_name, parent_field, nil, &block)
      @schema.parent_tables << table
      table
    end

    def child_table(table_name, child_field, &block)
      table = create_table(table_name, nil, child_field, &block)
      @schema.child_tables << table
      table
    end

    def self.build(&block)
      schema = Schema.new
      helper = new(schema)
      helper.instance_eval(&block)
      schema
    end

    private

    def create_table(table_name, parent_field, child_field, &block)
      table = Table.new(table_name, parent_field, child_field)
      build_nested_schema(table, &block) if block
      table
    end

    def build_nested_schema(table, &block)
      helper = self.class.new(table.nested_schema)
      helper.instance_eval(&block)
    end
  end
end
