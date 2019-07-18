# frozen_string_literal: true

module DBPurger
  # DBPurger::Table is an entity to keep track of basic table data
  class Table
    DEFAULT_BATCH_SIZE = 10_000

    attr_accessor :foreign_key,
                  :batch_size,
                  :conditions,
                  :search_proc

    attr_reader :name,
                :field

    def initialize(name, field)
      @name = name
      @field = field
      @batch_size = DEFAULT_BATCH_SIZE
    end

    def nested_schema(&block)
      @nested_schema ||= Schema.new
      SchemaBuilder.new(@nested_schema).build_nested_schema(self, &block) if block
      @nested_schema
    end

    def nested_tables?
      @nested_schema != nil
    end

    def tables
      @nested_schema ? @nested_schema.tables : []
    end

    def foreign_keys
      @nested_schema ? @nested_schema.tables.map(&:foreign_key).compact : []
    end

    def fields
      [@field] + foreign_keys
    end
  end
end
