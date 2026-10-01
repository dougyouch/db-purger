# frozen_string_literal: true
require 'spec_helper'
require 'support/throwaway_db'

describe DBPurger::DynamicPlanBuilder do
  let(:database) { DYNAMIC_DATABASE }
  let(:base_table_name) { :companies }
  let(:field) { :id }
  let(:dynamic_plan_builder) { DBPurger::DynamicPlanBuilder.new(database) }

  context '#build' do
    let(:expected_output) do
<<-STR
base_table(:companies, :id)

parent_table(:company_tags, :company_id)
parent_table(:employments, :company_id) do
  child_table(:employment_notes, :employment_id)
  child_table(:stats_employment_durations, :employment_id)
end
parent_table(:stats_company_employments, :company_id)

ignore_table :contents
ignore_table :events
ignore_table :jobs
ignore_table :tags
ignore_table :users
ignore_table :websites
STR
    end
    subject { dynamic_plan_builder.build(base_table_name, field) }

    it 'creates a purge plan' do
      expect(subject).to eq(expected_output)
    end

    # table listing order varies by platform/adapter; the generated plan must not
    it 'is independent of the order database.models returns tables in' do
      allow(database).to receive(:models).and_return(database.models.reverse)
      expect(subject).to eq(expected_output)
    end

    describe 'none primary_key field' do
      let(:base_table_name) { :employments }
      let(:field) { :company_id }
      let(:expected_output) do
<<-STR
base_table(:employments, :company_id)

parent_table(:company_tags, :company_id)
parent_table(:stats_company_employments, :company_id)

child_table(:employment_notes, :employment_id)
child_table(:stats_employment_durations, :employment_id)

ignore_table :companies
ignore_table :contents
ignore_table :events
ignore_table :jobs
ignore_table :tags
ignore_table :users
ignore_table :websites
STR
      end

      it 'creates a purge plan' do
        expect(subject).to eq(expected_output)
      end
    end
  end

  context '#build with a non primary key field and no child tables' do
    it 'lists the sibling parent_tables without an empty child section' do
      expect(dynamic_plan_builder.build(:stats_company_employments, :company_id)).to eq(<<~STR)
        base_table(:stats_company_employments, :company_id)

        parent_table(:company_tags, :company_id)
        parent_table(:employments, :company_id) do
          child_table(:employment_notes, :employment_id)
          child_table(:stats_employment_durations, :employment_id)
        end

        ignore_table :companies
        ignore_table :contents
        ignore_table :events
        ignore_table :jobs
        ignore_table :tags
        ignore_table :users
        ignore_table :websites
      STR
    end
  end

  context '#build_for' do
    subject { dynamic_plan_builder.build_for(:company_id) }

    it 'makes every table holding the field a top-level parent_table' do
      expect(subject).to eq(<<~STR)
        parent_table(:company_tags, :company_id)

        parent_table(:employments, :company_id) do
          child_table(:employment_notes, :employment_id)
          child_table(:stats_employment_durations, :employment_id)
        end

        parent_table(:stats_company_employments, :company_id)

        ignore_table :companies
        ignore_table :contents
        ignore_table :events
        ignore_table :jobs
        ignore_table :tags
        ignore_table :users
        ignore_table :websites
      STR
    end
  end

  context 'schemas the association walk has to handle' do
    name = 'dynamic_plan_builder_test'
    models = Module.new
    DynamicPlanBuilderTestModels = models

    before(:all) do
      @database = ThrowawayDB.create(name, models, [
        'CREATE TABLE companies (id INTEGER PRIMARY KEY)',
        'CREATE TABLE employments (id INTEGER PRIMARY KEY, company_id INTEGER)',
        'CREATE TABLE employment_stats (id INTEGER PRIMARY KEY, employment_id INTEGER)',
        'CREATE UNIQUE INDEX index_employment_stats_on_employment_id ON employment_stats (employment_id)',
        'CREATE TABLE a_things (id INTEGER PRIMARY KEY, company_id INTEGER, b_thing_id INTEGER)',
        'CREATE TABLE b_things (id INTEGER PRIMARY KEY, a_thing_id INTEGER)',
        'CREATE TABLE legacy_things (company_id INTEGER, name TEXT)',
        'CREATE TABLE legacy_thing_notes (id INTEGER PRIMARY KEY, legacy_thing_id INTEGER)'
      ])
    end
    after(:all) { ThrowawayDB.destroy(name, @database) }

    let(:database) { @database }

    it 'nests has_one tables, comments out cycles and does not nest under tables without a primary key' do
      expect(dynamic_plan_builder.build(:companies, :id)).to eq(<<~STR)
        base_table(:companies, :id)

        parent_table(:a_things, :company_id) do
          child_table(:b_things, :a_thing_id) do
            # child_table(:a_things, :b_thing_id) skipped: cycle back to a_things
          end
        end
        parent_table(:employments, :company_id) do
          child_table(:employment_stats, :employment_id)
        end
        parent_table(:legacy_things, :company_id)
        # legacy_things has no primary key; cannot nest legacy_thing_notes

        ignore_table :legacy_thing_notes
      STR
    end

    it 'flags a table without a primary key that other tables reference' do
      expect(dynamic_plan_builder.build_for(:company_id)).to include(<<~STR)
        parent_table(:legacy_things, :company_id)
        # legacy_things has no primary key; cannot nest legacy_thing_notes
      STR
    end
  end
end
