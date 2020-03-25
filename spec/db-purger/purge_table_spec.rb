require 'spec_helper'

describe DBPurger::PurgeTable do
  let(:database) { DYNAMIC_DATABASE }
  let(:plan) do
    DBPurger::PlanBuilder.build do
      base_table(:companies, :id)

      child_table(:employments, :company_id, batch_size: 2) do
        child_table(:employment_notes, :employment_id, batch_size: 1)
      end

      parent_table(:company_tags, :company_id)
    end
  end

  context '#purge!' do
    let(:table_name) { :companies }
    let(:field) { :id }
    let(:foreign_key) { nil }
    let(:batch_size) { 2 }
    let(:table) { DBPurger::Table.new(table_name, field).tap { |t| t.batch_size = batch_size; t.foreign_key = foreign_key } }
    let(:purge_field) { :id }
    let(:purge_value) { 1 }
    let(:purge_table) { DBPurger::PurgeTable.new(database, table, purge_field, purge_value) }
    subject { purge_table.purge! }

    describe 'simple deletion' do
      let(:company1) { create :company, id: 1 }
      let(:company2) { create :company, id: 2 }

      before(:each) do
        company1
        company2
      end

      after(:each) do
        reset_test_database
      end

      it 'purges company 1' do
        expect {
          subject
        }.to change { TestDB::Company.count }.by(-1)
      end
    end

    describe 'nested deletion' do
      subject { plan.purge!(DYNAMIC_DATABASE, purge_value) }
      let(:company1) do
        create(:company, id: 1).tap do |c|
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
          end
        end
      end
      let(:company2) do
        create(:company, id: 2).tap do |c|
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
            create(:employment_note, employment: employment)
          end
          create(:employment, company: c).tap do |employment|
            create(:employment_note, employment: employment)
          end
        end
      end
      let(:company3) do |c|
        create(:company, id: 3).tap do |c|
          create(:company_tag, company: c)
          create(:company_tag, company: c)
          create(:company_tag, company: c)
        end
      end

      before(:each) do
        company1
        company2
        company3.delete
      end

      after(:each) do
        reset_test_database
      end

      it 'purges company 1 and associated data' do
        expect {
          expect {
            expect {
              subject
            }.to change { TestDB::EmploymentNote.count }.by(-14)
          }.to change { TestDB::Employment.count }.by(-7)
        }.to change { TestDB::Company.count }.by(-1)
      end

      describe 'parent_table' do
        let(:purge_value) { 3 }

        it 'removes data from parent tables' do
          expect {
            expect {
              subject
            }.to change { TestDB::CompanyTag.count }.by(-3)
          }.to change { TestDB::Company.count }.by(0)
        end
      end
    end
  end
end
