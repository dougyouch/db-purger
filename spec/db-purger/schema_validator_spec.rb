require 'spec_helper'

describe DBPurger::SchemaValidator do
  let(:database) { DYNAMIC_DATABASE }
  let(:purge_value) { 1 }
  let(:schema_validator) { DBPurger::SchemaValidator.new(database, schema) }

  context '#valid?' do
    subject { schema_validator.valid? }

    let(:schema) do
      DBPurger::SchemaBuilder.build do
        base_table(:companies, :id)

        parent_table(:company_tags, :company_id)
        parent_table(:stats_company_employments, :company_id)

        child_table(:employments, :company_id) do
          child_table(:employment_notes, :employment_id)
          child_table(:stats_employment_durations, :employment_id)
        end

        ignore_table :users
        ignore_table :jobs
        ignore_table /web/
        ignore_table :tags
      end
    end

    it 'returns true if all table definitions are correct' do
      expect(subject).to eq(true)
    end

    describe 'missing_tables' do
      let(:schema) do
        DBPurger::SchemaBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
          end

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
        end
      end

      it 'returns false if missing tables' do
        expect(subject).to eq(false)
        expect(schema_validator.errors[:missing_tables].empty?).to eq(false)
        expect(schema_validator.errors[:table].empty?).to eq(true)
        expect(schema_validator.errors[:unknown_tables].empty?).to eq(true)
      end
    end

    describe 'unknown_tables' do
      let(:schema) do
        DBPurger::SchemaBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
            child_table(:employment_statuses, :employment_id)
          end

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
          ignore_table :tags
        end
      end

      it 'returns false if unknown tables' do
        expect(subject).to eq(false)
        expect(schema_validator.errors[:missing_tables].empty?).to eq(true)
        expect(schema_validator.errors[:table].empty?).to eq(false)
        expect(schema_validator.errors[:unknown_tables].empty?).to eq(false)
      end
    end

    describe 'invalid table definition' do
      let(:schema) do
        DBPurger::SchemaBuilder.build do
          base_table(:companies, :id)

          parent_table(:company_tags, :company_id)
          parent_table(:stats_company_employments, :company_id)

          child_table(:employments, :bad_company_id) do
            child_table(:employment_notes, :employment_id)
            child_table(:stats_employment_durations, :employment_id)
          end

          ignore_table :users
          ignore_table :jobs
          ignore_table :websites
          ignore_table :tags
        end
      end

      it 'returns false if bad table definitions' do
        expect(subject).to eq(false)
        expect(schema_validator.errors[:missing_tables].empty?).to eq(true)
        expect(schema_validator.errors[:table].empty?).to eq(false)
        expect(schema_validator.errors[:unknown_tables].empty?).to eq(true)
      end
    end
  end
end
