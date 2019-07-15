module DBPurger
  class Table
    attr_reader :name,
                :parent_field,
                :child_field

    def initialize(name, parent_field, child_field)
      @name = name
      @parent_field = parent_field
      @child_field = child_field
    end

    def nested_schema
      @nested_schema ||= Schema.new
    end

    def table_names
      if @nested_schema
        [@name] + @nested_schema.table_names
      else
        [@name]
      end
    end
  end
end
