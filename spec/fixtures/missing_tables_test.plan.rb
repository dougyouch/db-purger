base_table(:companies, :id)

parent_table(:company_tags, :company_id)
parent_table(:stats_company_employments, :company_id)

child_table(:employments, :company_id) do
  child_table(:employment_notes, :employment_id)
  child_table(:stats_employment_durations, :employment_id)
  child_table(:events, :model_id, conditions: {model_type: 'Employment'})
end

child_table(:events, :model_id, conditions: {model_type: 'Company'})

child_table(:websites, :id, foreign_key: :website_id)
child_table(:websites, :id, foreign_key: :company_website_id)

purge_table_search(:users, :id) do |users|
  users = users.index_by(&:id)
  TestDB::Employment.select(:id, :user_id).where('user_id IN(?)', users.keys).each do |record|
    users.delete(record.user_id)
  end
  users.values
end.nested_plan do
  child_table(:events, :model_id, conditions: {model_type: 'TestDB::User'})
end
