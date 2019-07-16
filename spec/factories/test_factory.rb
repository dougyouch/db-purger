FactoryBot.define do
  factory :company, class: 'TestDB::Company' do
    name { 'Company ' + SecureRandom.hex(8) }
  end
end
