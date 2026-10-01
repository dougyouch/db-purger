# frozen_string_literal: true

require 'support/throwaway_db'

# An outreach product keyed by oid (no organizations table): emails, sms_messages and calls are each
# a top-level table with their own sub tables. Real FOREIGN KEY constraints make purge order mistakes fail.
module OutreachDB
  NAME = 'outreach_test'

  # namespace for the generated models
  Models = Module.new

  SCHEMA = [
    'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)',
    'CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT)',
    'CREATE TABLE emails (id INTEGER PRIMARY KEY, oid INTEGER NOT NULL, ' \
    'user_id INTEGER REFERENCES users(id), subject TEXT)',
    # email_id is nullable: a recipient can exist without its email
    'CREATE TABLE email_recipients (id INTEGER PRIMARY KEY, oid INTEGER NOT NULL, ' \
    'email_id INTEGER REFERENCES emails(id), address TEXT)',
    'CREATE TABLE email_events (id INTEGER PRIMARY KEY, ' \
    'email_recipient_id INTEGER NOT NULL REFERENCES email_recipients(id), name TEXT)',
    # unique foreign key => has_one
    'CREATE TABLE email_attachments (id INTEGER PRIMARY KEY, ' \
    'email_id INTEGER NOT NULL REFERENCES emails(id), filename TEXT)',
    'CREATE UNIQUE INDEX index_email_attachments_on_email_id ON email_attachments (email_id)',
    'CREATE TABLE sms_messages (id INTEGER PRIMARY KEY, oid INTEGER NOT NULL, body TEXT)',
    'CREATE TABLE sms_deliveries (id INTEGER PRIMARY KEY, ' \
    'sms_message_id INTEGER NOT NULL REFERENCES sms_messages(id), status TEXT)',
    # a call may be logged from an email, so calls must be purged before emails
    'CREATE TABLE calls (id INTEGER PRIMARY KEY, oid INTEGER NOT NULL, ' \
    'user_id INTEGER REFERENCES users(id), email_id INTEGER REFERENCES emails(id), duration INTEGER)',
    'CREATE TABLE call_recordings (id INTEGER PRIMARY KEY, ' \
    'call_id INTEGER NOT NULL REFERENCES calls(id), url TEXT)',
    'CREATE UNIQUE INDEX index_call_recordings_on_call_id ON call_recordings (call_id)',
    'CREATE TABLE call_notes (id INTEGER PRIMARY KEY, call_id INTEGER NOT NULL REFERENCES calls(id), note TEXT)',
    # join table, no primary key => has_and_belongs_to_many calls <-> tags
    'CREATE TABLE call_tags (call_id INTEGER NOT NULL REFERENCES calls(id), ' \
    'tag_id INTEGER NOT NULL REFERENCES tags(id))'
  ].freeze

  def self.create
    ThrowawayDB.create(NAME, Models, SCHEMA)
  end

  def self.clean(database)
    ThrowawayDB.clean(database)
  end

  def self.destroy(database)
    ThrowawayDB.destroy(NAME, database)
  end
end
