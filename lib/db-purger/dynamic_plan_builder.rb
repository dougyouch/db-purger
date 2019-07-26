# frozen_string_literal: true

module DBPurger
  # DBPurger::DynamicPlanBuilder generates a purge plan based on the database relations
  class DynamicPlanBuilder
    INDENT = '  '

    attr_reader :output

    def initialize(database)
      @database = database
      @output = ''.dup
      @indent_depth = 0
      @tables = []
    end

    def build(base_table_name, field)
      write_table('base', base_table_name.to_s, field, [], nil)
      line_break
      model = find_model_for_table(base_table_name)
      foreign_key = foreign_key_name(model)
      add_parent_tables(base_table_name, field) unless field == :id
      unless (child_models = find_child_models(model, foreign_key)).empty?
        line_break unless field == :id
        add_child_tables(child_models, foreign_key, 0)
      end
      ignore_missing_tables
      @output
    end

    private

    def find_model_for_table(base_table_name)
      @database.models.detect { |m| m.table_name == base_table_name.to_s }
    end

    def write(str)
      @output << (INDENT * @indent_depth) + str + "\n"
    end

    def line_break
      @output << "\n"
    end

    def add_parent_tables(base_table_name, field)
      @database.models.each do |model|
        next if model.table_name == base_table_name.to_s
        next unless column?(model, field)

        foreign_key = foreign_key_name(model)
        write_table('parent', model.table_name, field, find_child_models(model, foreign_key), foreign_key)
      end
    end

    def add_child_tables(child_models, field, change_indent_by = 1)
      @indent_depth += change_indent_by
      child_models.each do |model|
        add_child_table(model, field)
      end
      @indent_depth -= change_indent_by
    end

    def add_child_table(model, field)
      foreign_key = foreign_key_name(model)
      write_table('child', model.table_name, field, find_child_models(model, foreign_key), foreign_key)
    end

    def find_child_models(model, field)
      model_has_many_associations(model).map(&:klass).select { |m| column?(m, field) }
    end

    def model_has_many_associations(model)
      model.reflect_on_all_associations.select do |assoc|
        assoc.is_a?(ActiveRecord::Reflection::HasManyReflection)
      end
    end

    def foreign_key_name(model)
      model.table_name.singularize + '_id'
    end

    def column?(model, field)
      model.columns.detect { |c| c.name == field.to_s } != nil
    end

    def write_table(table_type, table_name, field, child_models, foreign_key)
      @tables << table_name
      if child_models.empty?
        write("#{table_type}_table(#{table_name.to_sym.inspect}, #{field.to_sym.inspect})")
      else
        write("#{table_type}_table(#{table_name.to_sym.inspect}, #{field.to_sym.inspect}) do")
        add_child_tables(child_models, foreign_key)
        write('end')
      end
    end

    def ignore_missing_tables
      missing_tables = @database.models.map(&:table_name) - @tables
      return if missing_tables.empty?

      line_break
      missing_tables.each do |table_name|
        write("ignore_table #{table_name.to_sym.inspect}")
      end
    end
  end
end
