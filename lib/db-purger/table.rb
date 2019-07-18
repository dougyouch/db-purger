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

    def nested_plan(&block)
      @nested_plan ||= Plan.new
      PlanBuilder.new(@nested_plan).build_nested_plan(self, &block) if block
      @nested_plan
    end

    def nested_tables?
      @nested_plan != nil
    end

    def tables
      @nested_plan ? @nested_plan.tables : []
    end

    def foreign_keys
      @nested_plan ? @nested_plan.tables.map(&:foreign_key).compact : []
    end

    def fields
      [@field] + foreign_keys
    end
  end
end
