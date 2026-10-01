# frozen_string_literal: true

require 'spec_helper'
require 'support/outreach_db'
require 'support/outreach_seeder'

# End-to-end purge of one org from a schema with several top-level tables (emails, sms_messages, calls),
# asserting every row of the purged org is gone and every other row is still there.
describe 'multi-root purge plans' do
  PURGE_OID = 1

  GENERATED_PLAN = <<~PLAN
    parent_table(:calls, :oid) do
      child_table(:call_notes, :call_id)
      child_table(:call_recordings, :call_id)
      child_table(:call_tags, :call_id)
    end

    parent_table(:email_recipients, :oid) do
      child_table(:email_events, :email_recipient_id)
    end

    parent_table(:emails, :oid) do
      child_table(:email_attachments, :email_id)
    end

    parent_table(:sms_messages, :oid) do
      child_table(:sms_deliveries, :sms_message_id)
    end

    ignore_table :tags
    ignore_table :users
  PLAN

  # same plan by hand, with tiny batches so every level pages through several batches
  HAND_WRITTEN_PLAN = <<~PLAN
    parent_table(:calls, :oid, batch_size: 2) do
      child_table(:call_notes, :call_id, batch_size: 1)
      child_table(:call_recordings, :call_id)
      child_table(:call_tags, :call_id)
    end

    parent_table(:email_recipients, :oid, batch_size: 2) do
      child_table(:email_events, :email_recipient_id, batch_size: 1)
    end

    parent_table(:emails, :oid, batch_size: 2) do
      child_table(:email_attachments, :email_id)
    end

    parent_table(:sms_messages, :oid, batch_size: 2) do
      child_table(:sms_deliveries, :sms_message_id, batch_size: 1)
    end

    ignore_table :tags
    ignore_table :users
  PLAN

  # the pre-existing style: one base_table, the other roots as its parent_tables (purged before its rows)
  BASE_TABLE_PLAN = <<~PLAN
    base_table(:emails, :oid, batch_size: 2)

    child_table(:email_attachments, :email_id)

    parent_table(:calls, :oid, batch_size: 2) do
      child_table(:call_notes, :call_id)
      child_table(:call_recordings, :call_id)
      child_table(:call_tags, :call_id)
    end
    parent_table(:email_recipients, :oid, batch_size: 2) do
      child_table(:email_events, :email_recipient_id)
    end
    parent_table(:sms_messages, :oid, batch_size: 2) do
      child_table(:sms_deliveries, :sms_message_id)
    end

    ignore_table :tags
    ignore_table :users
  PLAN

  def build_plan(source)
    DBPurger::PlanBuilder.build { instance_eval(source) }
  end

  def table_names
    database.models.map(&:table_name).sort
  end

  def remaining_rows
    table_names.to_h { |table_name| [table_name, OutreachSeeder.row_keys(database, table_name)] }
  end

  before(:all) { @database = OutreachDB.create }
  after(:all) { OutreachDB.destroy(@database) }

  let(:database) { @database }
  let!(:seeder) do
    OutreachDB.clean(database)
    OutreachSeeder.new(database, PURGE_OID).seed!
  end

  it 'enforces foreign keys, so a wrong purge order fails instead of passing silently' do
    expect(database.models.first.connection.select_value('PRAGMA foreign_keys')).to eq(1)

    emails_first = build_plan(<<~PLAN)
      parent_table(:emails, :oid)
      parent_table(:calls, :oid)
    PLAN
    expect { emails_first.purge!(database, PURGE_OID) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'seeds rows to purge and rows to keep in every table' do
    expect(seeder.expected_kept.keys.sort).to eq(table_names)
    expect(seeder.expected_purged.keys.sort).to eq(table_names - %w[tags users])
  end

  it 'generates one top-level parent_table per oid table, ordered for foreign keys' do
    expect(DBPurger::DynamicPlanBuilder.new(database).build_for(:oid)).to eq(GENERATED_PLAN)
  end

  {
    'generated plan' => GENERATED_PLAN,
    'hand-written plan with small batches' => HAND_WRITTEN_PLAN,
    'base_table plan' => BASE_TABLE_PLAN
  }.each do |description, source|
    describe description do
      let(:plan) { build_plan(source) }

      it 'is valid' do
        validator = DBPurger::PlanValidator.new(database, plan)
        expect(validator.valid?).to eq(true), validator.errors.full_messages.join(', ')
      end

      it "deletes every row of the purged org and keeps every other row" do
        plan.purge!(database, PURGE_OID)

        remaining = remaining_rows
        table_names.each do |table_name|
          expect(remaining[table_name]).to eq(seeder.expected_kept[table_name].sort), table_name
          expect(remaining[table_name] & seeder.expected_purged[table_name]).to eq([]), table_name
        end
      end

      it 'is a no-op when run again' do
        plan.purge!(database, PURGE_OID)
        after_first = remaining_rows

        expect(plan.purge!(database, PURGE_OID)).to eq(0)
        expect(remaining_rows).to eq(after_first)
      end
    end
  end

  it 'returns the number of root table rows deleted' do
    # 3 calls + 7 email_recipients (2 per email + 1 without one) + 3 emails + 3 sms_messages
    expect(build_plan(GENERATED_PLAN).purge!(database, PURGE_OID)).to eq(16)
  end

  it 'purges a recipient whose email_id is null, which nesting under emails would miss' do
    orphan = database.get_model!('email_recipients').where(oid: PURGE_OID, email_id: nil)
    expect(orphan.count).to eq(1)

    build_plan(GENERATED_PLAN).purge!(database, PURGE_OID)
    expect(orphan.count).to eq(0)
  end
end
