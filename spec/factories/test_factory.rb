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
end
