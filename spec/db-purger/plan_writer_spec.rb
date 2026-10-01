# frozen_string_literal: true

require 'spec_helper'

describe DBPurger::PlanWriter do
  let(:writer) { DBPurger::PlanWriter.new }

  it 'renders tables, nested blocks and comments, tracking the tables written' do
    writer.table_block('parent', 'emails', :oid) do
      writer.table('child', 'email_attachments', 'email_id')
      writer.comment('a note')
    end

    expect(writer.output).to eq(<<~STR)
      parent_table(:emails, :oid) do
        child_table(:email_attachments, :email_id)
        # a note
      end
    STR
    expect(writer.table_names).to eq(%w[emails email_attachments])
  end

  describe '#ignore_tables' do
    it 'writes a blank line then one ignore_table per table' do
      writer.ignore_tables(%w[tags users])
      expect(writer.output).to eq("\nignore_table :tags\nignore_table :users\n")
    end

    it 'writes nothing when every table is in the plan' do
      writer.ignore_tables([])
      expect(writer.output).to eq('')
    end
  end
end
