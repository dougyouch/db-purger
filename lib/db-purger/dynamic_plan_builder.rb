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
      write('DBPurger::PlanBuilder.build do')
      @indent_depth += 1
    end

    def build(base_table_name, field)
      write("base_table(#{base_table_name.to_sym.inspect}, #{field.to_sym.inspect})")
      line_break
      model = find_model_for_table(base_table_name)
      child_field = foreign_key_name(model)
      add_parent_tables(base_table_name, child_field)
      unless (child_models = find_child_models(model, child_field)).empty?
        line_break
        add_child_tables(child_models, child_field)
      end
      @indent_depth -= 1
      write('end')
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

        child_field = foreign_key_name(model)
        if (child_models = find_child_models(model, child_field)).empty?
          write("parent_table(#{model.table_name.to_sym.inspect}, #{field.to_sym.inspect})")
        else
          write("parent_table(#{model.table_name.to_sym.inspect}, #{field.to_sym.inspect}) do")
          @indent_depth += 1
          add_child_tables(child_models, child_field)
          @indent_depth -= 1
          write('end')
        end
      end
    end

    def add_child_tables(child_models, field)
      child_models.each do |model|
        add_child_table(model, field)
      end
    end

    def add_child_table(model, field)
      child_field = foreign_key_name(model)
      if (child_models = find_child_models(model, child_field)).empty?
        write("child_table(#{model.table_name.to_sym.inspect}, #{field.to_sym.inspect})")
      else
        write("child_table(#{model.table_name.to_sym.inspect}, #{field.to_sym.inspect}) do")
        @indent_depth += 1
        add_child_tables(child_models, child_field)
        @indent_depth -= 1
        write('end')
      end
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
  end
end
