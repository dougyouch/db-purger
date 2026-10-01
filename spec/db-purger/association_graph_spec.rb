# frozen_string_literal: true

require 'spec_helper'
require 'support/throwaway_db'

describe DBPurger::AssociationGraph do
  name = 'association_graph_test'
  AssociationGraphTestModels = Module.new

  before(:all) do
    @database = ThrowawayDB.create(name, AssociationGraphTestModels, [
      'CREATE TABLE users (id INTEGER PRIMARY KEY)',
      'CREATE TABLE companies (id INTEGER PRIMARY KEY)',
      'CREATE TABLE employments (id INTEGER PRIMARY KEY, company_id INTEGER, user_id INTEGER)',
      'CREATE TABLE events (id INTEGER PRIMARY KEY, model_type TEXT, model_id INTEGER)'
    ])

    company = AssociationGraphTestModels::Company
    # polymorphic: matching on model_id alone would purge other models' events
    company.has_many :events, as: :model, class_name: AssociationGraphTestModels::Event.name
    # through: reached via employments' own associations instead
    company.has_many :employment_users, through: :employments, source: :user
    # habtm whose join table is not part of the database
    company.has_and_belongs_to_many :ghost_users, join_table: 'missing_join',
                                                  class_name: AssociationGraphTestModels::User.name
  end
  after(:all) { ThrowawayDB.destroy(name, @database) }

  let(:graph) { DBPurger::AssociationGraph.new(@database) }

  describe '#edges' do
    it 'keeps direct foreign keys and skips polymorphic, through and join-table-less associations' do
      edges = graph.edges(AssociationGraphTestModels::Company)
      expect(edges.map { |edge| [edge.model.table_name, edge.foreign_key] }).to eq([%w[employments company_id]])
    end
  end

  describe '#reachable' do
    it 'collects every model referencing the model, transitively' do
      expect(graph.reachable(AssociationGraphTestModels::User).map(&:table_name)).to eq(%w[employments])
    end
  end
end
