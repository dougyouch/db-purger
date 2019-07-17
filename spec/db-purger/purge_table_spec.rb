require 'spec_helper'

describe DBPurger::PurgeTable do
  let(:database) { DYNAMIC_DATABASE }
  let(:schema) do
    DBPurger::SchemaBuilder.build do
      base_table(:companies, :id)

      child_table(:employments, :company_id, batch_size: 2) do
        child_table(:employment_notes, :employment_id, batch_size: 1)
      end
    end
  end

  context '#purge!' do
    let(:table_name) { :companies }
    let(:field) { :id }
    let(:parent_field) { nil }
    let(:batch_size) { 2 }
    let(:table) { DBPurger::Table.new(table_name, field, parent_field, batch_size) }
    let(:purge_field) { :id }
    let(:purge_value) { 1 }
    let(:purge_table) { DBPurger::PurgeTable.new(database, table, purge_field, purge_value) }
    subject { purge_table.purge! }

    describe 'simple deletion' do
      let(:company1) { create :company, id: purge_value }
      let(:company2) { create :company }

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
      subject { schema.purge!(DYNAMIC_DATABASE, purge_value) }
      let(:company1) do
        create(:company, id: purge_value).tap do |c|
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
        create(:company).tap do |c|
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

      before(:each) do
        company1
        company2
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
    end
  end
end
