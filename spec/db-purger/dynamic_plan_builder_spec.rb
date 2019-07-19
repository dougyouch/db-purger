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
DBPurger::PlanBuilder.build do
  base_table(:companies, :id)

  parent_table(:employments, :company_id) do
    child_table(:employment_notes, :employment_id)
    child_table(:stats_employment_durations, :employment_id)
  end
  parent_table(:company_tags, :company_id)
  parent_table(:stats_company_employments, :company_id)

  child_table(:employments, :company_id) do
    child_table(:employment_notes, :employment_id)
    child_table(:stats_employment_durations, :employment_id)
  end
  child_table(:company_tags, :company_id)
  child_table(:stats_company_employments, :company_id)

  ignore_table :users
  ignore_table :jobs
  ignore_table :websites
  ignore_table :tags
  ignore_table :events
end
STR
    end
    subject { dynamic_plan_builder.build(base_table_name, field) }

    it 'creates a purge plan' do
      expect(subject).to eq(expected_output)
    end
  end
end
