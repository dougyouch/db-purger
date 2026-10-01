# frozen_string_literal: true

module DBPurger
  # DBPurger::PlanWriter renders plan DSL source and tracks which tables it has written
  class PlanWriter
    INDENT = '  '

    attr_reader :output,
                :table_names

    def initialize
      @output = ''.dup
      @indent_depth = 0
      @table_names = []
    end

    def table(table_type, table_name, field)
      @table_names << table_name
      write(table_call(table_type, table_name, field))
    end

    def table_block(table_type, table_name, field)
      @table_names << table_name
      write("#{table_call(table_type, table_name, field)} do")
      @indent_depth += 1
      yield
      @indent_depth -= 1
      write('end')
    end

    def comment(str)
      write("# #{str}")
    end

    def ignore_tables(table_names)
      return if table_names.empty?

      line_break
      table_names.each { |table_name| write("ignore_table #{table_name.to_sym.inspect}") }
    end

    def line_break
      @output << "\n"
    end

    private

    def write(str)
      @output << "#{INDENT * @indent_depth}#{str}\n"
    end

    def table_call(table_type, table_name, field)
      "#{table_type}_table(#{table_name.to_sym.inspect}, #{field.to_sym.inspect})"
    end
  end
end
