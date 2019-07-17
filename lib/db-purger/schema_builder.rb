# frozen_string_literal: true

module DBPurger
  # DBPurger::SchemaBuilder is used to build the relationships between tables in a convenient way
  class SchemaBuilder
    def initialize(schema)
      @schema = schema
    end

    def base_table(table_name, field, options = {}, &block)
      @schema.base_table = create_table(table_name, field, options, &block)
    end

    def parent_table(table_name, field, options = {}, &block)
      table = create_table(table_name, field, options, &block)
      if @schema.base_table
        @schema.base_table.nested_schema.parent_tables << table
      else
        @schema.parent_tables << table
      end
      table
    end

    def child_table(table_name, field, options = {}, &block)
      table = create_table(table_name, field, options, &block)
      if @schema.base_table
        @schema.base_table.nested_schema.child_tables << table
      else
        @schema.child_tables << table
      end
      table
    end

    def ignore_table(table_name)
      @schema.ignore_tables << table_name
    end

    def self.build(&block)
      schema = Schema.new
      helper = new(schema)
      helper.instance_eval(&block)
      schema
    end

    private

    def create_table(table_name, field, options, &block)
      table = Table.new(table_name, field)
      table.foreign_key = options[:foreign_key]
      table.batch_size = options[:batch_size]
      table.conditions = options[:conditions]
      build_nested_schema(table, &block) if block
      table
    end

    def build_nested_schema(table, &block)
      helper = self.class.new(table.nested_schema)
      helper.instance_eval(&block)
    end
  end
end
