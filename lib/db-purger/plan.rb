# frozen_string_literal: true

module DBPurger
  # DBPurger::Plan is used to describe the relationship between tables
  class Plan
    attr_accessor :base_table

    attr_reader :parent_tables,
                :child_tables,
                :ignore_tables,
                :search_tables

    def initialize
      @parent_tables = []
      @child_tables = []
      @ignore_tables = []
      @search_tables = []
    end

    def purge!(database, purge_value)
      raise('plan has no base_table or top-level parent_table') if root_tables.empty?
      raise('top-level child_tables require a base_table') unless @base_table || @child_tables.empty?

      MetricSubscriber.reset!
      num_deleted = purge_root_tables(database, purge_value)
      purge_search_tables(database)
      MetricSubscriber.finished!
      num_deleted
    end

    # tables that receive the purge value directly: the base_table (if any) and top-level parent_tables
    def root_tables
      (@base_table ? [@base_table] : []) + @parent_tables
    end

    def tables
      all_tables = @base_table ? [@base_table] + @base_table.tables : []
      all_tables += @parent_tables + @parent_tables.map(&:tables) +
                    @child_tables + @child_tables.map(&:tables) +
                    @search_tables + @search_tables.map(&:tables)
      all_tables.flatten!
      all_tables.compact!
      all_tables
    end

    # the tables of a nested plan (nested plans never have a base_table)
    def foreign_tables
      @parent_tables + @child_tables + @search_tables
    end

    def table_names
      tables.map(&:name)
    end

    def empty?
      @base_table.nil? &&
        @parent_tables.empty? &&
        @child_tables.empty? &&
        @search_tables.empty?
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

    private

    def purge_root_tables(database, purge_value)
      root_tables.sum do |table|
        PurgeTable.new(database, table, table.field, purge_value).purge!
      end
    end

    # with a base_table these live in its nested plan and are purged by it
    def purge_search_tables(database)
      @search_tables.each do |table|
        PurgeTableScanner.new(database, table).purge!
      end
    end
  end
end
