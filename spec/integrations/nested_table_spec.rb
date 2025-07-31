require 'spec_helper'

describe 'nested table' do
  let(:database) { DYNAMIC_DATABASE }
  let(:purge_value) { 1 }
  let(:plan) do
    DBPurger::PlanBuilder.build do
      base_table(:employments, :company_id, batch_size: 2)
      child_table(:employment_notes, :employment_id, batch_size: 1)
    end
  end

  subject { plan.purge!(database, purge_value) }

  let!(:tag1) { create :tag }
  let!(:tag2) { create :tag }
  let!(:tag3) { create :tag }
  let!(:tag4) { create :tag }
  let!(:tag5) { create :tag }
  let!(:company1) do
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
      create(:company_tag, company: c, tag: tag2)
      create(:company_tag, company: c, tag: tag3)
      create(:company_tag, company: c, tag: tag5)
    end
  end
  let!(:company2) do
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

  it 'purges company 1 and associated data' do
    expect {
      expect {
        expect {
          expect {
            expect {
              subject
            }.to change { TestDB::EmploymentNote.count }.by(-15)
          }.to change { TestDB::Employment.count }.by(-8)
        }.to change { TestDB::Company.count }.by(0)
      }.to change { TestDB::CompanyTag.count }.by(0)
    }.to change { TestDB::Tag.count }.by(0)
  end
end
