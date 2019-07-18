# frozen_string_literal: true

module DBPurger
  # DBPurger::PlanValidator is used to ensure that all tables in the database are part of the purge plan.
  #  It verifies that all table definitions are correct as well, checking that child/parent fields are part
  #  of the table.
  class PlanValidator
    include ActiveModel::Validations

    validate :validate_no_missing_tables
    validate :validate_no_unknown_tables
    validate :validate_tables

    def initialize(database, plan)
      @database = database
      @plan = plan
    end

    # tables that are part of the database but not part of the plan
    def missing_tables
      database_table_names - @plan.table_names.map(&:to_s)
    end

    # tables that are part of the plan put not part of the database
    def unknown_tables
      @plan.table_names.map(&:to_s) - database_table_names
    end

    private

    def validate_no_missing_tables
      errors.add(:missing_tables, missing_tables.sort.join(',')) unless missing_tables.empty?
    end

    def validate_no_unknown_tables
      errors.add(:unknown_tables, unknown_tables.sort.join(',')) unless unknown_tables.empty?
    end

    def validate_tables
      @plan.tables.each { |table| validate_table_definition(table) }
    end

    def validate_table_definition(table)
      unless (model = find_model_for_table(table))
        errors.add(:table, "#{table.name} has no model")
        return
      end

      table.fields.each do |field|
        unless model.column_names.include?(field.to_s)
          errors.add(:table, "#{table.name}.#{field} is missing in the database")
        end
      end
    end

    def find_model_for_table(table)
      @database.models.detect { |model| model.table_name == table.name.to_s }
    end

    def filter_table_names(table_names)
      table_names.reject { |table_name| @plan.ignore_table?(table_name) }
    end

    def database_table_names
      @database_table_names ||= filter_table_names(@database.models.map(&:table_name))
    end
  end
end
