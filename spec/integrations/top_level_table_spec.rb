require 'spec_helper'

describe 'top level table' do
  let(:database) { DYNAMIC_DATABASE }
  let(:purge_value) { 1 }
  let(:schema) do
    DBPurger::SchemaBuilder.build do
      base_table(:companies, :id)

      parent_table(:company_tags, :company_id)

      child_table(:employments, :company_id, batch_size: 2) do
        child_table(:employment_notes, :employment_id, batch_size: 1)

        child_table(:events, :model_id, conditions: {model_type: 'TestDB::Employment'})
      end

      child_table(:websites, :id, foreign_key: :website_id)
      child_table(:websites, :id, foreign_key: :company_website_id)

      child_table(:events, :model_id, conditions: {model_type: 'TestDB::Company'})

      purge_table_search(:users, :id, batch_size: 2) do |users|
        users = users.index_by(&:id)
        TestDB::Employment.select(:id, :user_id).where('user_id IN(?)', users.keys).each do |record|
          users.delete(record.user_id)
        end
        users.values
      end.nested_schema do
        child_table(:events, :model_id, conditions: {model_type: 'TestDB::User'})
      end
    end
  end

  subject { schema.purge!(database, purge_value) }

  let!(:tag1) { create :tag }
  let!(:tag2) { create :tag }
  let!(:tag3) { create :tag }
  let!(:tag4) { create :tag }
  let!(:tag5) { create :tag }
  let!(:company1) do
    create(:company, id: purge_value, website: create(:website), company_website: create(:website)).tap do |c|
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
        create(:event, model: employment.user)
      end
      create(:employment, company: c).tap do |employment|
        create(:employment_note, employment: employment)
        create(:event, model: employment)
      end
      create(:employment, company: c).tap do |employment|
        create(:employment_note, employment: employment)
        create(:employment_note, employment: employment)
      end
      create(:employment, company: c).tap do |employment|
        create(:employment_note, employment: employment)
      end
      create(:company_tag, company: c, tag: tag2)
      create(:company_tag, company: c, tag: tag3)
      create(:company_tag, company: c, tag: tag5)

      create(:event, model: c)
    end
  end
  let!(:company2) do
    create(:company, website: create(:website), company_website: create(:website)).tap do |c|
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
      create(:company_tag, company: c, tag: tag1)
      create(:company_tag, company: c, tag: tag3)
      create(:company_tag, company: c, tag: tag4)
      create(:event, model: c)
      create(:event, model: c)
    end
  end
  let!(:company1_employment2) do
    create(:employment, company: company1).tap do |employment|
      create(:employment_note, employment: employment)
      create(:event, model: employment)
    end
  end
  
  after(:each) do
    reset_test_database
  end

  it 'purges company 1 and associated data' do
    expect {
      expect {
        expect {
          expect {
            expect {
              expect {
                expect {
                  expect {
                    expect(subject).to eq(1)
                  }.to change { TestDB::EmploymentNote.count }.by(-15)
                }.to change { TestDB::Employment.count }.by(-8)
              }.to change { TestDB::User.count }.by(-8)
            }.to change { TestDB::Company.count }.by(-1)
          }.to change { TestDB::CompanyTag.count }.by(-3)
        }.to change { TestDB::Tag.count }.by(0)
      }.to change { TestDB::Website.count }.by(-2)
    }.to change { TestDB::Event.count }.by(-4)
  end

  describe 'explains' do
    before(:each) do
      ::DBPurger.config.explain = true
      ::DBPurger.config.explain_file = StringIO.new
    end

    after(:each) do
      ::DBPurger.config.explain = false
      ::DBPurger.config.explain_file = nil
    end

    it 'explains how it would delete company 1' do
      expect {
        expect {
          expect {
            expect {
              expect {
                expect {
                  expect {
                    expect {
                      expect(subject).to eq(1)
                    }.to change { TestDB::EmploymentNote.count }.by(0)
                  }.to change { TestDB::Employment.count }.by(0)
                }.to change { TestDB::User.count }.by(0)
              }.to change { TestDB::Company.count }.by(0)
            }.to change { TestDB::CompanyTag.count }.by(0)
          }.to change { TestDB::Tag.count }.by(0)
        }.to change { TestDB::Website.count }.by(0)
      }.to change { TestDB::Event.count }.by(0)

      expect(DBPurger::TestSubscriber.tables[:employments][:deleted]).to eq(8)
    end
  end
end
