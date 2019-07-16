require 'spec_helper'

describe DBPurger::PurgeTable do
  let(:database) { DYNAMIC_DATABASE }

  context '#purge!' do
    let(:table_name) { :companies }
    let(:parent_field) { :id }
    let(:child_field) { nil }
    let(:batch_size) { 2 }
    let(:table) { DBPurger::Table.new(table_name, parent_field, child_field, batch_size) }
    let(:purge_field) { :id }
    let(:purge_value) { 1 }
    let(:purge_table) { DBPurger::PurgeTable.new(database, table, purge_field, purge_value) }
    subject { purge_table.purge! }

    describe 'simple deletion' do
      let(:company1) { create :company, id: 1 }
      let(:company2) { create :company }

      before(:each) do
        company1
        company2
      end

      it 'purges company 1' do
        expect {
          subject
        }.to change { TestDB::Company.count }.by(-1)
      end
    end
  end
end
