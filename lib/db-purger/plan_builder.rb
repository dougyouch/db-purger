# frozen_string_literal: true

module DBPurger
  # DBPurger::PlanBuilder is used to build the relationships between tables in a convenient way
  class PlanBuilder
    def initialize(plan)
      @plan = plan
    end

    def base_table(table_name, field, options = {}, &block)
      @plan.base_table = create_table(table_name, field, options, &block)
    end

    def parent_table(table_name, field, options = {}, &block)
      table = create_table(table_name, field, options, &block)
      if @plan.base_table
        @plan.base_table.nested_plan.parent_tables << table
      else
        @plan.parent_tables << table
      end
      table
    end

    def child_table(table_name, field, options = {}, &block)
      table = create_table(table_name, field, options, &block)
      if @plan.base_table
        @plan.base_table.nested_plan.child_tables << table
      else
        @plan.child_tables << table
      end
      table
    end

    def ignore_table(table_name)
      @plan.ignore_tables << table_name
    end

    def purge_table_search(table_name, field, options = {}, &block)
      table = create_table(table_name, field, options)
      table.search_proc = block || raise('no block given for search_proc')
      if @plan.base_table
        @plan.base_table.nested_plan.search_tables << table
      else
        @plan.search_tables << table
      end
      table
    end

    def self.build(&block)
      plan = Plan.new
      helper = new(plan)
      helper.instance_eval(&block)
      plan
    end

    def build_nested_plan(table, &block)
      helper = self.class.new(table.nested_plan)
      helper.instance_eval(&block)
    end

    private

    def create_table(table_name, field, options, &block)
      table = Table.new(table_name, field)
      table.foreign_key = options[:foreign_key]
      table.batch_size = options[:batch_size] if options[:batch_size]
      table.conditions = options[:conditions]
      table.mark_deleted_field = options[:mark_deleted_field]
      table.mark_deleted_value = options[:mark_deleted_value]
      build_nested_plan(table, &block) if block
      table
    end
  end
end
