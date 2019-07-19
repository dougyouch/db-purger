# frozen_string_literal: true

FactoryBot.define do
  factory :company, class: 'TestDB::Company' do
    name { 'Company ' + SecureRandom.hex(8) }
  end

  factory :user, class: 'TestDB::User' do
    name { 'User ' + SecureRandom.hex(8) }
  end

  factory :job, class: 'TestDB::Job' do
    title { 'Job ' + SecureRandom.hex(8) }
  end

  factory :website, class: 'TestDB::Website' do
    url { 'https://' + SecureRandom.hex(8) + '.example.com' }
  end

  factory :employment, class: 'TestDB::Employment' do
    user
    job
    company
    started_at { Time.now }
  end

  factory :employment_note, class: 'TestDB::EmploymentNote' do
    employment
    note { 'Employee Note ' + SecureRandom.hex(8) }
  end

  factory :tag, class: 'TestDB::Tag' do
    name { 'Tag ' + SecureRandom.hex(8) }
  end

  factory :company_tag, class: 'TestDB::CompanyTag' do
    company
    tag
  end

  factory :event, class: 'TestDB::Event' do
    name { 'Event ' + SecureRandom.hex(8) }
    occurred_at { Time.now }
  end

  factory :stats_employment_duration, class: 'TestDB::StatsEmploymentDuration' do
    employment
    duration { rand(60..720) }
  end

  factory :stats_company_employment, class: 'TestDB::StatsCompanyEmployment' do
    company
    average_duration { rand(365..720) }
    num_jobs { rand(5..10_000) }
    total_employees_lifetime { rand(100..100_000) }
    num_current_employees { rand(5..10_000) }
    num_employees_for_current_year { rand(5..10_000) }
  end
end
