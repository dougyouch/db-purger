require 'spec_helper'

describe DBPurger::SchemaBuilder do
  let(:schema) { DBPurger::Schema.new }
  let(:builder) { DBPurger::SchemaBuilder.new(schema) }
  let(:table_name) { ('my_table_' + SecureRandom.hex(8)).to_sym }

  context '#base_table' do
    subject { builder.base_table(table_name, :parent_id) }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(table_name)
      expect(subject.field).to eq(:parent_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '#parent_table' do
    subject { builder.parent_table :my_parent_table, :parent_id }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(:my_parent_table)
      expect(subject.field).to eq(:parent_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '#child_table' do
    subject { builder.child_table :my_child_table, :child_id }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(:my_child_table)
      expect(subject.field).to eq(:child_id)
      expect(subject.foreign_key).to eq(nil)
    end
  end

  context '.build' do
    subject do
      DBPurger::SchemaBuilder.build do
        base_table(:my_base_table, :parent_id) do
          parent_table :my_parent_table, :parent_id
          child_table :my_child_table, :child_id
        end
      end
    end

    let(:base_table) { subject.base_table }

    it 'builds a schema' do
      expect(subject.base_table.name).to eq(:my_base_table)
      expect(subject.base_table.field).to eq(:parent_id)
      expect(subject.base_table.foreign_key).to eq(nil)
      expect(subject.table_names).to eq([:my_base_table, :my_parent_table, :my_child_table])
      expect(base_table.nested_schema.parent_tables.first.name).to eq(:my_parent_table)
      expect(base_table.nested_schema.parent_tables.first.field).to eq(:parent_id)
      expect(base_table.nested_schema.parent_tables.first.foreign_key).to eq(nil)
      expect(base_table.nested_schema.parent_tables.first.nested_schema.empty?).to eq(true)
      expect(base_table.nested_schema.child_tables.first.name).to eq(:my_child_table)
      expect(base_table.nested_schema.child_tables.first.field).to eq(:child_id)
      expect(base_table.nested_schema.child_tables.first.foreign_key).to eq(nil)
      expect(base_table.nested_schema.child_tables.first.nested_schema.empty?).to eq(true)
    end
  end
end
