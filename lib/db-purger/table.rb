# frozen_string_literal: true

module DBPurger
  # DBPurger::Table is an entity to keep track of basic table data
  class Table
    DEFAULT_BATCH_SIZE = 10_000

    attr_accessor :foreign_key,
                  :batch_size,
                  :conditions

    attr_reader :name,
                :field

    def initialize(name, field)
      @name = name
      @field = field
      @batch_size = DEFAULT_BATCH_SIZE
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

    def foreign_keys
      @nested_schema ? @nested_schema.tables.map(&:foreign_key).compact : []
    end

    def fields
      [@field] + foreign_keys
    end
  end
end
