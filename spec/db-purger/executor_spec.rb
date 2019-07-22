# frozen_string_literal: true

require 'spec_helper'

describe DBPurger::Executor do
  let(:database) { DYNAMIC_DATABASE }
  let(:plan) { 'spec/fixtures/test.plan.rb' }
  let(:options) do
    {
      explain: nil,
      explain_file: nil,
      datetime_format: nil
    }
  end
  let(:error_io) { StringIO.new }
  let(:error_msg) { error_io.seek(0); error_io.read }
  let(:executor) { DBPurger::Executor.new(database, plan, options).tap { |exe| exe.error_io = error_io } }

  describe '#verify!' do
    subject { executor.verify! }

    it 'valid purge plan' do
      subject
      expect(error_msg.size).to eq(0)
    end

    describe 'missing tables' do
      let(:plan) { 'spec/fixtures/missing_tables_test.plan.rb' }
      let(:expected_error_msg) { "missing_tables: jobs,tags\n" }

      it 'raises an exception' do
        expect { subject }.to raise_error(RuntimeError)
        expect(error_msg).to eq(expected_error_msg)
      end
    end

    describe 'unknown tables' do
      let(:plan) { 'spec/fixtures/unknown_tables_test.plan.rb' }
      let(:expected_error_msg) { "unknown_tables: event_handlers\ntable: event_handlers has no model\n" }

      it 'raises an exception' do
        expect { subject }.to raise_error(RuntimeError)
        expect(error_msg).to eq(expected_error_msg)
      end
    end
  end

  describe '#purge!' do
    let(:purge_value) { 1 }
    subject { executor.purge!(purge_value) }

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
          create(:stats_employment_duration, employment: employment)
        end
        create(:employment, company: c).tap do |employment|
          create(:employment_note, employment: employment)
          create(:stats_employment_duration, employment: employment)
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
          create(:stats_employment_duration, employment: employment)
        end
        create(:employment, company: c).tap do |employment|
          create(:employment_note, employment: employment)
          create(:event, model: employment)
          create(:stats_employment_duration, employment: employment)
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
        create(:stats_company_employment, company: c)
        create(:stats_company_employment, company: c)
        create(:stats_company_employment, company: c)
        create(:stats_company_employment, company: c)
      end
    end
    let!(:company2) do
      create(:company, website: create(:website), company_website: create(:website)).tap do |c|
        create(:employment, company: c).tap do |employment|
          create(:employment_note, employment: employment)
          create(:employment_note, employment: employment)
          create(:stats_employment_duration, employment: employment)
        end
        create(:employment, company: c).tap do |employment|
          create(:employment_note, employment: employment)
          create(:employment_note, employment: employment)
          create(:stats_employment_duration, employment: employment)
        end
        create(:employment, company: c).tap do |employment|
          create(:employment_note, employment: employment)
          create(:stats_employment_duration, employment: employment)
        end
        create(:company_tag, company: c, tag: tag1)
        create(:company_tag, company: c, tag: tag3)
        create(:company_tag, company: c, tag: tag4)
        create(:event, model: c)
        create(:event, model: c)
        create(:stats_company_employment, company: c)
        create(:stats_company_employment, company: c)
      end
    end
    let!(:company1_employment2) do
      create(:employment, company: company1).tap do |employment|
        create(:employment_note, employment: employment)
        create(:event, model: employment)
        create(:stats_employment_duration, employment: employment)
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
                      expect {
                        expect {
                          expect(subject).to eq(1)
                        }.to change { TestDB::StatsEmploymentDuration.count }.by(-5)
                      }.to change { TestDB::StatsCompanyEmployment.count }.by(-4)
                    }.to change { TestDB::EmploymentNote.count }.by(-15)
                  }.to change { TestDB::Employment.count }.by(-8)
                }.to change { TestDB::User.count }.by(-8)
              }.to change { TestDB::Company.count }.by(-1)
            }.to change { TestDB::CompanyTag.count }.by(-3)
          }.to change { TestDB::Tag.count }.by(0)
        }.to change { TestDB::Website.count }.by(-2)
      }.to change { TestDB::Event.count }.by(-4)
    end
  end
end
