# frozen_string_literal: true

module DBPurger
  class SchemaBuilder
    def initialize(schema)
      @schema = schema
    end

    def top_table(table_name, parent_field, child_field = nil, batch_size = nil, &block)
      @schema.top_table = create_table(table_name, parent_field, child_field, batch_size, &block)
    end

    def parent_table(table_name, parent_field, child_field = nil, batch_size = nil, &block)
      table = create_table(table_name, parent_field, child_field, batch_size, &block)
      if @schema.top_table
        @schema.top_table.parent_tables << table
      else
        @schema.parent_tables << table
      end
      table
    end

    def child_table(table_name, child_field, batch_size = nil, &block)
      table = create_table(table_name, nil, child_field, batch_size, &block)
      if @schema.top_table
        @schema.top_table.nested_schema.child_tables << table
      else
        @schema.child_tables << table
      end
      table
    end

    def self.build(&block)
      schema = Schema.new
      helper = new(schema)
      helper.instance_eval(&block)
      schema
    end

    private

    def create_table(table_name, parent_field, child_field, batch_size, &block)
      table = Table.new(table_name, parent_field, child_field, batch_size)
      build_nested_schema(table, &block) if block
      table
    end

    def build_nested_schema(table, &block)
      helper = self.class.new(table.nested_schema)
      helper.instance_eval(&block)
    end
  end
end
