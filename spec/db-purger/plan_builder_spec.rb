require 'spec_helper'

describe DBPurger::PlanBuilder do
  let(:plan) { DBPurger::Plan.new }
  let(:builder) { DBPurger::PlanBuilder.new(plan) }
  let(:table_name) { ('my_table_' + SecureRandom.hex(8)).to_sym }

  context '#base_table' do
    subject { builder.base_table(table_name, :parent_id) }

    it 'creates a top table with a nested plan' do
      expect(subject.name).to eq(table_name)
      expect(subject.field).to eq(:parent_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '#parent_table' do
    subject { builder.parent_table :my_parent_table, :parent_id }

    it 'creates a top table with a nested plan' do
      expect(subject.name).to eq(:my_parent_table)
      expect(subject.field).to eq(:parent_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '#child_table' do
    subject { builder.child_table :my_child_table, :child_id }

    it 'creates a top table with a nested plan' do
      expect(subject.name).to eq(:my_child_table)
      expect(subject.field).to eq(:child_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '#nullify_table' do
    it 'nests under the base_table' do
      base = builder.base_table(:my_base_table, :id)
      table = builder.nullify_table(:my_base_table, :source_id, conditions: { active: true })

      expect(base.nested_plan.nullify_tables).to eq([table])
      expect(table.field).to eq(:source_id)
      expect(table.conditions).to eq(active: true)
    end

    it 'rejects options that only make sense when deleting' do
      expect { builder.nullify_table(:my_table, :source_id, batch_size: 5, foreign_key: :x) }
        .to raise_error(ArgumentError, 'nullify_table does not support :batch_size, :foreign_key')
    end
  end

  context '.build' do
    subject do
      DBPurger::PlanBuilder.build do
        base_table(:my_base_table, :parent_id) do
          parent_table :my_parent_table, :parent_id
          child_table :my_child_table, :child_id
        end
      end
    end

    let(:base_table) { subject.base_table }

    it 'builds a plan' do
      expect(subject.base_table.name).to eq(:my_base_table)
      expect(subject.base_table.field).to eq(:parent_id)
      expect(subject.base_table.foreign_key).to eq(nil)
      expect(subject.table_names).to eq([:my_base_table, :my_parent_table, :my_child_table])
      expect(base_table.nested_plan.parent_tables.first.name).to eq(:my_parent_table)
      expect(base_table.nested_plan.parent_tables.first.field).to eq(:parent_id)
      expect(base_table.nested_plan.parent_tables.first.foreign_key).to eq(nil)
      expect(base_table.nested_plan.parent_tables.first.nested_plan.empty?).to eq(true)
      expect(base_table.nested_plan.child_tables.first.name).to eq(:my_child_table)
      expect(base_table.nested_plan.child_tables.first.field).to eq(:child_id)
      expect(base_table.nested_plan.child_tables.first.foreign_key).to eq(nil)
      expect(base_table.nested_plan.child_tables.first.nested_plan.empty?).to eq(true)
    end
  end
end
