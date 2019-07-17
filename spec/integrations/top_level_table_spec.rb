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
      end

      child_table(:websites, :id, parent_field: :website_id)
      child_table(:websites, :id, parent_field: :company_website_id)
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
      create(:company_tag, company: c, tag: tag2)
      create(:company_tag, company: c, tag: tag3)
      create(:company_tag, company: c, tag: tag5)
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
    end
  end
  let!(:company1_employment2) do
    create(:employment, company: company1).tap do |employment|
      create(:employment_note, employment: employment)
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
                subject
              }.to change { TestDB::EmploymentNote.count }.by(-15)
            }.to change { TestDB::Employment.count }.by(-8)
          }.to change { TestDB::Company.count }.by(-1)
        }.to change { TestDB::CompanyTag.count }.by(-3)
      }.to change { TestDB::Tag.count }.by(0)
    }.to change { TestDB::Website.count }.by(-2)
  end
end
