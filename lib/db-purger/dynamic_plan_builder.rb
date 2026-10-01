# frozen_string_literal: true

module DBPurger
  # DBPurger::DynamicPlanBuilder generates a purge plan based on the database relations
  class DynamicPlanBuilder
    def initialize(database)
      @graph = AssociationGraph.new(database)
      @writer = PlanWriter.new
    end

    def output
      @writer.output
    end

    # plan rooted at a single base table
    def build(base_table_name, field)
      model = @graph.model_for(base_table_name)
      @writer.table('base', model.table_name, field)
      @writer.line_break
      if model.primary_key == field.to_s
        add_referencing_parent_tables(model)
      else
        add_sibling_parent_tables(model, field)
        add_base_child_tables(model)
      end
      finish
    end

    # plan with one top-level parent_table per table holding field (e.g. :oid), each purged by field
    # directly so rows with a null foreign key are not missed; the tables referencing each root are nested
    # under it, and roots are ordered so a root referencing another root's rows is purged first
    def build_for(field)
      @root_field = field.to_s
      ordered_root_models.each_with_index do |model, idx|
        @writer.line_break if idx.positive?
        write_table('parent', model, field, [])
      end
      finish
    end

    private

    def finish
      @writer.ignore_tables(@graph.models.map(&:table_name) - @writer.table_names)
      output
    end

    # base_table(:companies, :id): tables holding companies.id are keyed directly on the purge value
    def add_referencing_parent_tables(model)
      @graph.edges(model).each { |edge| write_edge('parent', edge, [model]) }
    end

    # base_table(:employments, :company_id): other tables holding company_id share the purge value
    def add_sibling_parent_tables(model, field)
      @graph.models.each do |sibling|
        next if sibling == model || !@graph.column?(sibling, field)

        write_table('parent', sibling, field, [model])
      end
    end

    def add_base_child_tables(model)
      edges = nestable_edges(model)
      return if edges.empty?

      @writer.line_break
      edges.each { |edge| write_edge('child', edge, [model]) }
    end

    def write_edge(table_type, edge, ancestors)
      if ancestors.include?(edge.model)
        @writer.comment("#{table_type}_table(#{edge.model.table_name.to_sym.inspect}, " \
                        "#{edge.foreign_key.to_sym.inspect}) skipped: cycle back to #{edge.model.table_name}")
      else
        write_table(table_type, edge.model, edge.foreign_key, ancestors)
      end
    end

    def write_table(table_type, model, field, ancestors)
      edges = nestable_edges(model)
      if edges.empty?
        @writer.table(table_type, model.table_name, field)
        warn_unnestable(model)
      else
        @writer.table_block(table_type, model.table_name, field) do
          edges.each { |edge| write_edge('child', edge, ancestors + [model]) }
        end
      end
    end

    # purging nested tables needs this table's primary keys to propagate
    def nestable_edges(model)
      return [] unless model.primary_key

      @graph.edges(model).reject { |edge| root_model?(edge.model) }
    end

    def root_model?(model)
      @root_field && @graph.column?(model, @root_field)
    end

    def warn_unnestable(model)
      return if model.primary_key || (edges = @graph.edges(model)).empty?

      @writer.comment("#{model.table_name} has no primary key; cannot nest " \
                      "#{edges.map { |edge| edge.model.table_name }.join(', ')}")
    end

    # repeatedly take the first root (by name) whose referencing roots are already written; on a cycle,
    # fall back to name order so no root is dropped
    def ordered_root_models
      remaining = @graph.models.select { |model| root_model?(model) }
      ordered = []
      until remaining.empty?
        model = remaining.detect { |root| (purged_first(root) & remaining).empty? } || remaining.first
        ordered << remaining.delete(model)
      end
      ordered
    end

    # roots holding rows that reference root's rows (directly or through nested tables)
    def purged_first(root)
      @graph.reachable(root).select { |model| model != root && root_model?(model) }
    end
  end
end
