# frozen_string_literal: true

require 'spec_helper'
require 'support/throwaway_db'

# A self-referential, nullable foreign key: a cadence copied from a template keeps a link to it, templates are
# copied from templates, and another org may copy a template it does not own. Real FOREIGN KEY constraints make
# a purge that deletes a template before the cadences pointing at it fail.
describe 'nullify_table' do
  NULLIFY_DB_NAME = 'nullify_test'
  NullifyDB = Module.new unless defined?(NullifyDB)

  before(:all) do
    @database = ThrowawayDB.create(
      NULLIFY_DB_NAME,
      NullifyDB,
      [
        'CREATE TABLE cadences (id INTEGER PRIMARY KEY, oid INTEGER NOT NULL, ' \
        'source_cadence_id INTEGER REFERENCES cadences(id), name TEXT)',
        'CREATE TABLE cadence_steps (id INTEGER PRIMARY KEY, ' \
        'cadence_id INTEGER NOT NULL REFERENCES cadences(id), ' \
        'copied_from_cadence_id INTEGER NOT NULL REFERENCES cadences(id))'
      ]
    )
  end

  after(:all) { ThrowawayDB.destroy(NULLIFY_DB_NAME, @database) }

  before(:each) { ThrowawayDB.clean(@database) }

  after(:each) do
    ::DBPurger.config.explain = false
    ::DBPurger.config.explain_file = nil
  end

  let(:database) { @database }
  let(:cadences) { NullifyDB::Cadence }

  # one row per batch, so every link crosses a batch boundary
  let(:plan) do
    DBPurger::PlanBuilder.build do
      base_table(:cadences, :oid, batch_size: 1)
      nullify_table(:cadences, :source_cadence_id)
      ignore_table :cadence_steps
    end
  end

  def create_cadence(id, oid, source_cadence_id = nil)
    cadences.create!(id: id, oid: oid, source_cadence_id: source_cadence_id, name: "cadence #{id}")
  end

  # template 1 <- template 2 <- cadence 3, plus template 5 pointed at by the older cadence 4
  let!(:chain) do
    create_cadence(1, 1)
    create_cadence(2, 1, 1)
    create_cadence(3, 1, 2)
    create_cadence(5, 1)
    create_cadence(4, 1)
    cadences.where(id: 4).update_all(source_cadence_id: 5)
  end

  it 'fails on the foreign key without it' do
    without_nullify = DBPurger::PlanBuilder.build { base_table(:cadences, :oid, batch_size: 1) }

    expect { without_nullify.purge!(database, 1) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'unlinks every reference before deleting, whatever the chain depth or id order' do
    expect { plan.purge!(database, 1) }.not_to raise_error
    expect(cadences.count).to eq(0)
  end

  it 'keeps rows of other purge values and clears only their link to a deleted row' do
    create_cadence(10, 2, 1)
    create_cadence(11, 2, 10)

    plan.purge!(database, 1)

    expect(cadences.order(:id).pluck(:id, :source_cadence_id)).to eq([[10, nil], [11, 10]])
  end

  it 'applies conditions to the rows it unlinks' do
    create_cadence(10, 2, 1)
    create_cadence(11, 3, 1)
    conditional_plan = DBPurger::PlanBuilder.build do
      base_table(:cadences, :oid, batch_size: 1)
      nullify_table(:cadences, :source_cadence_id, conditions: { oid: [1, 2] })
    end

    expect { conditional_plan.purge!(database, 1) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(cadences.find(10).source_cadence_id).to eq(nil)
    expect(cadences.find(11).source_cadence_id).to eq(1)
  end

  it 'reports nullified rows separately from deleted rows' do
    plan.purge!(database, 1)

    # 2 -> 1 and 3 -> 2 are unlinked; cadence 4 is deleted in its own batch before cadence 5's batch runs
    stats = DBPurger::MetricSubscriber.metrics.as_json
    expect(stats[:nullify_stats][:cadences][:num_nullified]).to eq(2)
    expect(stats[:nullify_stats][:cadences][:num_nullify_queries]).to eq(5)
    expect(stats[:delete_stats][:cadences][:num_deleted]).to eq(5)
  end

  it 'writes the UPDATE in explain mode without changing anything' do
    explain_file = StringIO.new
    executor = DBPurger::Executor.new(database, plan, explain: true, explain_file: explain_file)

    expect { executor.purge!(1) }.not_to(change { cadences.order(:id).pluck(:id, :source_cadence_id) })
    expect(explain_file.string).to include('UPDATE "cadences" SET "source_cadence_id" = NULL WHERE')
  end

  describe 'validation' do
    def validator_for(&block)
      DBPurger::PlanValidator.new(database, DBPurger::PlanBuilder.build(&block))
    end

    it 'accepts a nullable column' do
      validator = DBPurger::PlanValidator.new(database, plan)
      expect(validator.valid?).to eq(true), validator.errors.full_messages.join(', ')
    end

    it 'rejects a NOT NULL column' do
      validator = validator_for do
        base_table(:cadences, :oid)
        child_table(:cadence_steps, :cadence_id)
        nullify_table(:cadence_steps, :copied_from_cadence_id)
      end

      expect(validator.valid?).to eq(false)
      expect(validator.errors[:table]).to eq(['cadence_steps.copied_from_cadence_id (nullify_table) is not nullable'])
    end

    it 'leaves a missing table or column to the table definition checks' do
      validator = validator_for do
        base_table(:cadences, :oid)
        nullify_table(:cadences, :missing_id)
        nullify_table(:missing_table, :cadence_id)
        ignore_table :cadence_steps
      end

      expect(validator.valid?).to eq(false)
      expect(validator.errors[:table]).to contain_exactly('cadences.missing_id is missing in the database',
                                                          'missing_table has no model')
    end

    it 'rejects a top-level nullify_table without a base_table' do
      top_level = DBPurger::PlanBuilder.build do
        parent_table(:cadences, :oid)
        nullify_table(:cadences, :source_cadence_id)
        ignore_table :cadence_steps
      end
      validator = DBPurger::PlanValidator.new(database, top_level)

      expect(validator.valid?).to eq(false)
      expect(validator.errors[:base_table]).to eq(['must be declared before top-level nullify_tables'])
      expect { top_level.purge!(database, 1) }.to raise_error(RuntimeError, /nullify_tables require a base_table/)
    end
  end

  it 'nests under a top-level parent_table' do
    nested = DBPurger::PlanBuilder.build do
      parent_table(:cadences, :oid, batch_size: 1) do
        nullify_table(:cadences, :source_cadence_id)
      end
    end

    expect { nested.purge!(database, 1) }.not_to raise_error
    expect(cadences.count).to eq(0)
  end
end
