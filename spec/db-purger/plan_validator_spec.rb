require 'spec_helper'

describe DBPurger::PlanValidator do
  let(:database) { DYNAMIC_DATABASE }
  let(:purge_value) { 1 }
  let(:plan_validator) { DBPurger::PlanValidator.new(database, plan) }

  context '#valid?' do
    subject { plan_validator.valid? }

    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:companies, :id)

        parent_table(:company_tags, :company_id)
        parent_table(:stats_company_employments, :company_id)

        child_table(:employments, :company_id) do
          child_table(:employment_notes, :employment_id)
          child_table(:stats_employment_durations, :employment_id)
          child_table(:events, :model_id, conditions: {model_type: 'Employment'})
        end

        child_table(:events, :model_id, conditions: {model_type: 'Company'})

        ignore_table :users
        ignore_table :jobs
        ignore_table /web/
        ignore_table :contents
        ignore_table :tags
      end
    end

    it 'returns true if all table definitions are correct' do
      expect(subject).to eq(true)
    end

    describe 'missing_tables' do
      let(:plan) do
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
          end

          child_table(:events, :model_id, conditions: {model_type: 'Company'})

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
          ignore_table :contents
        end
      end

      it 'returns false if missing tables' do
        expect(subject).to eq(false)
        expect(plan_validator.errors[:missing_tables].empty?).to eq(false)
        expect(plan_validator.errors[:table].empty?).to eq(true)
        expect(plan_validator.errors[:unknown_tables].empty?).to eq(true)
      end
    end

    describe 'unknown_tables' do
      let(:plan) do
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
            child_table(:employment_statuses, :employment_id)
          end

          child_table(:events, :model_id, conditions: {model_type: 'Company'})

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
          ignore_table :contents
          ignore_table :tags
        end
      end

      it 'returns false if unknown tables' do
        expect(subject).to eq(false)
        expect(plan_validator.errors[:missing_tables].empty?).to eq(true)
        expect(plan_validator.errors[:table].empty?).to eq(false)
        expect(plan_validator.errors[:unknown_tables].empty?).to eq(false)
      end
    end

    describe 'invalid table definition' do
      let(:plan) do
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :bad_company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
          end

          child_table(:events, :model_id, conditions: {model_type: 'Company'})

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
          ignore_table :contents
          ignore_table :tags
        end
      end

      it 'returns false if bad table definitions' do
        expect(subject).to eq(false)
        expect(plan_validator.errors[:missing_tables].empty?).to eq(true)
        expect(plan_validator.errors[:table].empty?).to eq(false)
        expect(plan_validator.errors[:unknown_tables].empty?).to eq(true)
      end
    end
  end
end
