# frozen_string_literal: true

module DBPurger
  # DBPurger::Schema is used to describe the relationship between tables
  class Schema
    attr_accessor :top_table

    attr_reader :parent_tables,
                :child_tables

    def initialize
      @parent_tables = []
      @child_tables = []
    end

    def purge!(database, purge_value)
      PurgeTable.new(database, @top_table, @top_table.parent_field, purge_value).purge!
    end

    def table_names
      names = @top_table ? @top_table.table_names : []
      names += @parent_tables.map(&:table_names)
      names += @child_tables.map(&:table_names)
      names.flatten!
      names.compact!
      names
    end

    def empty?
      @top_table.nil? &&
        @parent_tables.empty? &&
        @child_tables.empty?
    end
  end
end
