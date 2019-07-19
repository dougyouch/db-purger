# frozen_string_literal: true
require 'spec_helper'

describe DBPurger::DynamicPlanBuilder do
  let(:database) { DYNAMIC_DATABASE }
  let(:base_table_name) { :companies }
  let(:field) { :id }
  let(:dynamic_plan_builder) { DBPurger::DynamicPlanBuilder.new(database) }

  context '#build' do
    subject { dynamic_plan_builder.build(base_table_name, field) }

    it 'creates a purge plan' do
      puts subject
    end
  end
end
