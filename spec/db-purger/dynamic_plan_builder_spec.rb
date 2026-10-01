# frozen_string_literal: true
require 'spec_helper'

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
end
