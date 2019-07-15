require 'spec_helper'

describe DBPurger::SchemaBuilder do
  let(:schema) { DBPurger::Schema.new }
  let(:builder) { DBPurger::SchemaBuilder.new(schema) }
  let(:table_name) { ('my_table_' + SecureRandom.hex(8)).to_sym }

  context '#top_table' do
    subject { builder.top_table(table_name, :parent_id) }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(table_name)
      expect(subject.parent_field).to eq(:parent_id)
      expect(subject.child_field).to eq(nil)
    end
  end

  context '#parent_table' do
    subject { builder.parent_table :my_parent_table, :parent_id }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(:my_parent_table)
      expect(subject.parent_field).to eq(:parent_id)
      expect(subject.child_field).to eq(nil)
    end
  end

  context '#child_table' do
    subject { builder.child_table :my_child_table, :child_id }

    it 'creates a top table with a nested schema' do
      expect(subject.name).to eq(:my_child_table)
      expect(subject.parent_field).to eq(nil)
      expect(subject.child_field).to eq(:child_id)
    end
  end

  context '.build' do
    subject do
      DBPurger::SchemaBuilder.build do
        top_table(:my_top_table, :parent_id) do
          parent_table :my_parent_table, :parent_id
          child_table :my_child_table, :child_id
        end
      end
    end

    let(:top_table) { subject.top_table }

    it 'builds a schema' do
      expect(subject.top_table.name).to eq(:my_top_table)
      expect(subject.top_table.parent_field).to eq(:parent_id)
      expect(subject.top_table.child_field).to eq(nil)
      expect(subject.table_names).to eq([:my_top_table, :my_parent_table, :my_child_table])
      expect(top_table.nested_schema.parent_tables.first.name).to eq(:my_parent_table)
      expect(top_table.nested_schema.parent_tables.first.parent_field).to eq(:parent_id)
      expect(top_table.nested_schema.parent_tables.first.child_field).to eq(nil)
      expect(top_table.nested_schema.parent_tables.first.nested_schema.empty?).to eq(true)
      expect(top_table.nested_schema.child_tables.first.name).to eq(:my_child_table)
      expect(top_table.nested_schema.child_tables.first.parent_field).to eq(nil)
      expect(top_table.nested_schema.child_tables.first.child_field).to eq(:child_id)
      expect(top_table.nested_schema.child_tables.first.nested_schema.empty?).to eq(true)
    end
  end
end
