# frozen_string_literal: true

require 'spec_helper'
require 'sqlite3'

# Regression specs for purge-safety bugs: each example reproduces a failure
# that was previously silent or destructive.
describe 'purge safety' do
  let(:database) { DYNAMIC_DATABASE }

  after(:each) do
    ::DBPurger.config.explain = false
    ::DBPurger.config.explain_file = nil
  end

  describe 'explain mode' do
    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:companies, :id)
        parent_table(:company_tags, :company_id)
      end
    end
    let!(:company) { create(:company, id: 1).tap { |c| create(:company_tag, company: c) } }

    it 'stays a dry run when another executor is created before purge!' do
      dry_run = DBPurger::Executor.new(database, plan, explain: true, explain_file: StringIO.new)
      DBPurger::Executor.new(database, plan)

      expect { dry_run.purge!(1) }.not_to(change { TestDB::Company.count })
    end

    it 'does not leak explain mode into other executors' do
      DBPurger::Executor.new(database, plan, explain: true, explain_file: StringIO.new).purge!(1)

      expect { DBPurger::Executor.new(database, plan).purge!(1) }.to change { TestDB::Company.count }.by(-1)
    end

    it 'rejects non-boolean explain values instead of running for real' do
      expect do
        DBPurger::Executor.new(database, plan, explain: 'true', explain_file: StringIO.new).purge!(1)
      end.to raise_error(ArgumentError)
      expect(TestDB::Company.count).to eq(1)
    end
  end

  describe 'mark_deleted_value: false' do
    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:employments, :company_id)
        child_table(:stats_employment_durations, :employment_id,
                    mark_deleted_field: :deleted, mark_deleted_value: false)
      end
    end
    let!(:duration) do
      create(:stats_employment_duration, employment: create(:employment, company: create(:company, id: 1)),
                                         deleted: true)
    end

    it 'writes false rather than the default of 1' do
      plan.purge!(database, 1)
      expect(duration.reload.deleted).to eq(false)
    end
  end

  describe 'foreign_key column named like a Ruby method' do
    # companies.reload is a real column; record.send(:reload) calls ActiveRecord#reload instead
    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:companies, :id)
        child_table(:websites, :id, foreign_key: :reload)
      end
    end
    let!(:website) { create(:website) }
    let!(:company) do
      create(:company, id: 1).tap { |c| TestDB::Company.where(id: c.id).update_all(reload: website.id.to_s) }
    end

    it 'purges using the column value' do
      expect { plan.purge!(database, 1) }.to change { TestDB::Website.count }.by(-1)
    end
  end

  describe 'plan validation' do
    let(:validator) { DBPurger::PlanValidator.new(database, plan) }
    def ignore_others(builder, *keep)
      (DYNAMIC_DATABASE.models.map(&:table_name) - keep.map(&:to_s)).each { |t| builder.ignore_table(t) }
    end

    describe 'nested tables under a table without a primary key' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id)
          parent_table(:company_tags, :company_id) do
            child_table(:tags, :id, foreign_key: :tag_id)
          end
          spec.ignore_others(self, :companies, :company_tags, :tags)
        end
      end

      it 'is invalid' do
        expect(validator.valid?).to eq(false)
        expect(validator.errors[:table].join).to include('company_tags')
      end

      it 'refuses to purge rather than silently skipping the nested tables' do
        create(:company_tag, company: create(:company, id: 1))
        expect { plan.purge!(database, 1) }.to raise_error(RuntimeError, /company_tags/)
        expect(TestDB::Tag.count).to eq(1)
      end
    end

    describe 'mark_deleted_field that is not a column' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id)
          parent_table(:stats_company_employments, :company_id, mark_deleted_field: :deleted_att)
          spec.ignore_others(self, :companies, :stats_company_employments)
        end
      end

      it 'is invalid' do
        expect(validator.valid?).to eq(false)
        expect(validator.errors[:table].join).to include('stats_company_employments.deleted_att')
      end
    end

    describe 'batch_size of zero' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          base_table(:companies, :id, batch_size: 0)
          spec.ignore_others(self, :companies)
        end
      end

      it 'is invalid' do
        expect(validator.valid?).to eq(false)
        expect(validator.errors[:table].join).to include('batch_size')
      end
    end

    describe 'no base_table' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          child_table(:companies, :id)
          spec.ignore_others(self, :companies)
        end
      end

      it 'is invalid' do
        expect(validator.valid?).to eq(false)
        expect(validator.errors[:base_table]).not_to be_empty
      end

      it 'raises a clear error on purge!' do
        expect { plan.purge!(database, 1) }.to raise_error(RuntimeError, /base_table/)
      end
    end

    describe 'top-level parent_tables without a base_table' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          parent_table(:companies, :id)
          spec.ignore_others(self, :companies)
        end
      end

      it 'is valid' do
        expect(validator.valid?).to eq(true)
      end

      it 'purges each root by the purge value' do
        create(:company, id: 1)
        create(:company, id: 2)
        expect(plan.purge!(database, 1)).to eq(1)
        expect(TestDB::Company.pluck(:id)).to eq([2])
      end
    end

    describe 'top-level child_table alongside parent_tables without a base_table' do
      let(:plan) do
        spec = self
        DBPurger::PlanBuilder.build do
          parent_table(:companies, :id)
          child_table(:employments, :company_id)
          spec.ignore_others(self, :companies, :employments)
        end
      end

      it 'is invalid' do
        expect(validator.valid?).to eq(false)
        expect(validator.errors[:base_table].join).to include('top-level child_tables')
      end

      it 'is invalid when the child_table is declared before the base_table' do
        spec = self
        early_child = DBPurger::PlanBuilder.build do
          child_table(:employments, :company_id)
          base_table(:companies, :id)
          spec.ignore_others(self, :companies, :employments)
        end
        expect(DBPurger::PlanValidator.new(database, early_child).valid?).to eq(false)
      end

      it 'refuses to purge rather than skipping the child_table' do
        expect { plan.purge!(database, 1) }.to raise_error(RuntimeError, /top-level child_tables/)
      end
    end
  end

  describe 'top-level purge_table_search without a base_table' do
    let!(:company1) { create(:company, id: 1) }
    let!(:company2) { create(:company, id: 2) }
    let!(:orphan_a) { create(:user, name: 'orphan a') }
    let!(:orphan_b) { create(:user, name: 'orphan b') }
    let!(:kept_user) { create(:user, name: 'kept') }

    it 'runs after the roots and deletes only the records the search selects' do
      plan = DBPurger::PlanBuilder.build do
        parent_table(:companies, :id)
        purge_table_search(:users, :id) { |users| users.select { |user| user.name.start_with?('orphan') } }
      end

      expect(plan.purge!(database, 1)).to eq(1)
      expect(TestDB::Company.pluck(:id)).to eq([2])
      expect(TestDB::User.pluck(:id)).to eq([kept_user.id])
    end

    it 'applies conditions before the search sees the batch' do
      plan = DBPurger::PlanBuilder.build do
        parent_table(:companies, :id)
        purge_table_search(:users, :id, conditions: { name: 'orphan a' }) { |users| users }
      end

      plan.purge!(database, 1)
      expect(TestDB::User.pluck(:id).sort).to eq([orphan_b.id, kept_user.id].sort)
    end
  end

  describe 'conditions on a table without a primary key' do
    let!(:tag1) { create(:tag) }
    let!(:tag2) { create(:tag) }
    let!(:company1) { create(:company, id: 1) }
    let!(:company2) { create(:company, id: 2) }
    let!(:purged) { create(:company_tag, company: company1, tag: tag1) }

    before do
      create(:company_tag, company: company1, tag: tag2)
      create(:company_tag, company: company2, tag: tag1)
    end

    it 'adds the conditions to the single unbatched delete' do
      tag_id = tag1.id
      plan = DBPurger::PlanBuilder.build do
        parent_table(:company_tags, :company_id, conditions: { tag_id: tag_id })
      end

      plan.purge!(database, 1)
      expect(TestDB::CompanyTag.pluck(:company_id, :tag_id).sort)
        .to eq([[company1.id, tag2.id], [company2.id, tag1.id]].sort)
    end
  end

  describe 'foreign_key child whose values are all NULL' do
    let!(:company) { create(:company, id: 1, website_id: nil) }
    let!(:unrelated_website) { create(:website) }
    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:companies, :id)
        child_table(:websites, :id, foreign_key: :website_id)
      end
    end

    it 'never starts a purge of the child' do
      purged_tables = []
      subscriber = ->(*, payload) { purged_tables << payload[:table_name] }

      ActiveSupport::Notifications.subscribed(subscriber, 'purge.db_purger') do
        plan.purge!(database, 1)
      end

      expect(purged_tables).to eq([:companies])
      expect(TestDB::Company.count).to eq(0)
      expect(TestDB::Website.pluck(:id)).to eq([unrelated_website.id])
    end
  end

  describe 'parent_table with a real foreign key to the base table' do
    db_file = 'spec/fk_test.db'

    before(:all) do
      File.unlink(db_file) if File.exist?(db_file)
      SQLite3::Database.new(db_file).tap do |db|
        db.execute('CREATE TABLE companies (id INTEGER PRIMARY KEY, name TEXT)')
        db.execute('CREATE TABLE company_tags (id INTEGER PRIMARY KEY, ' \
                   'company_id INTEGER NOT NULL REFERENCES companies(id), name TEXT)')
        db.close
      end
      FkTestDB = Module.new unless defined?(FkTestDB)
      @fk_database = DynamicActiveModel::Database.new(FkTestDB, { adapter: 'sqlite3', database: db_file })
      @fk_database.create_models!
    end

    after(:each) do
      FkTestDB::CompanyTag.delete_all
      FkTestDB::Company.delete_all
    end

    after(:all) { File.unlink(db_file) if File.exist?(db_file) }

    let(:plan) do
      DBPurger::PlanBuilder.build do
        base_table(:companies, :id)
        parent_table(:company_tags, :company_id)
      end
    end

    it 'surfaces the database error instead of a metrics TypeError' do
      FkTestDB::Company.create!(id: 2, name: 'b')
      FkTestDB::CompanyTag.create!(company_id: 2, name: 'y')
      base_only = DBPurger::PlanBuilder.build { base_table(:companies, :id) }

      expect { base_only.purge!(@fk_database, 2) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'deletes the referencing rows before the base row' do
      FkTestDB::Company.create!(id: 1, name: 'a')
      FkTestDB::CompanyTag.create!(company_id: 1, name: 'x')

      expect { plan.purge!(@fk_database, 1) }.not_to raise_error
      expect(FkTestDB::Company.count).to eq(0)
      expect(FkTestDB::CompanyTag.count).to eq(0)
    end
  end
end
