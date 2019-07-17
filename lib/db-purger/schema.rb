# frozen_string_literal: true

module DBPurger
  # DBPurger::Schema is used to describe the relationship between tables
  class Schema
    attr_accessor :top_table

    attr_reader :parent_tables,
                :child_tables,
                :ignore_tables

    def initialize
      @parent_tables = []
      @child_tables = []
      @ignore_tables = []
    end

    def purge!(database, purge_value)
      PurgeTable.new(database, @top_table, @top_table.field, purge_value).purge!
    end

    def tables
      all_tables = @top_table ? [@top_table] + @top_table.tables : []
      all_tables += @parent_tables + @parent_tables.map(&:tables) +
                    @child_tables + @child_tables.map(&:tables)
      all_tables.flatten!
      all_tables.compact!
      all_tables
    end

    def table_names
      tables.map(&:name)
    end

    def empty?
      @top_table.nil? &&
        @parent_tables.empty? &&
        @child_tables.empty?
    end

    def ignore_table?(table_name)
      @ignore_tables.any? do |ignore_table_name|
        if ignore_table_name.is_a?(Regexp)
          ignore_table_name.match(table_name)
        else
          ignore_table_name.to_s == table_name
        end
      end
    end
  end
end
