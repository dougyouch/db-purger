# frozen_string_literal: true

module DBPurger
  # DBPurger::Table is an entity to keep track of basic table data
  class Table
    DEFAULT_BATCH_SIZE = 10_000

    attr_reader :name,
                :field,
                :parent_field,
                :batch_size

    def initialize(name, field, parent_field = nil, batch_size = nil)
      @name = name
      @field = field
      @parent_field = parent_field
      @batch_size = batch_size || DEFAULT_BATCH_SIZE
    end

    def nested_schema
      @nested_schema ||= Schema.new
    end

    def nested_tables?
      @nested_schema != nil
    end

    def tables
      @nested_schema ? @nested_schema.tables : []
    end
  end
end
