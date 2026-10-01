# frozen_string_literal: true

module DBPurger
  # DBPurger::AssociationGraph answers "which tables reference this model, and by which column" from the
  # has_many, has_one and has_and_belongs_to_many associations dynamic-active-model discovered
  class AssociationGraph
    # a table holding foreign_key that points at the parent model's primary key
    Edge = Struct.new(:model, :foreign_key)

    def initialize(database)
      @database = database
      @edges = {}
    end

    # database.models order depends on how the adapter lists tables, which varies by platform;
    # sort so generated plans are deterministic
    def models
      @models ||= @database.models.sort_by(&:table_name)
    end

    def model_for(table_name)
      models.detect { |model| model.table_name == table_name.to_s }
    end

    # one edge per (table, foreign key); a habtm join table also reached by a has_many appears once
    def edges(model)
      @edges[model] ||= model.reflect_on_all_associations
                             .filter_map { |reflection| edge_for(reflection) }
                             .uniq { |edge| edge_key(edge) }
                             .sort_by { |edge| edge_key(edge) }
    end

    # every model reachable from model through edges, excluding model itself unless there is a cycle
    def reachable(model, seen = Set.new)
      edges(model).each do |edge|
        next if seen.include?(edge.model)

        seen << edge.model
        reachable(edge.model, seen)
      end
      seen
    end

    def column?(model, field)
      model.column_names.include?(field.to_s)
    end

    private

    def edge_for(reflection)
      return if skip_reflection?(reflection)

      case reflection
      when ActiveRecord::Reflection::HasAndBelongsToManyReflection
        join_table_edge(reflection)
      when ActiveRecord::Reflection::HasManyReflection, ActiveRecord::Reflection::HasOneReflection
        Edge.new(reflection.klass, reflection.foreign_key.to_s)
      end
    end

    # through associations are reached via their own direct associations; polymorphic (as:) ones need a
    # type condition the generator cannot infer
    def skip_reflection?(reflection)
      reflection.options[:through] || reflection.options[:as]
    end

    def join_table_edge(reflection)
      join_model = model_for(reflection.join_table)
      Edge.new(join_model, reflection.foreign_key.to_s) if join_model
    end

    def edge_key(edge)
      [edge.model.table_name, edge.foreign_key]
    end
  end
end
