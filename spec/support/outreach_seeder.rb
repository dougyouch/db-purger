# frozen_string_literal: true

# Seeds two orgs of outreach data plus shared lookup rows into an OutreachDB database, recording for
# every table which row keys should survive a purge of purge_oid and which should be gone.
class OutreachSeeder
  ORGS = [1, 2].freeze

  attr_reader :expected_kept,
              :expected_purged

  def initialize(database, purge_oid)
    @database = database
    @purge_oid = purge_oid
    @expected_kept = Hash.new { |hsh, key| hsh[key] = [] }
    @expected_purged = Hash.new { |hsh, key| hsh[key] = [] }
  end

  def seed!
    @users = 2.times.map { |idx| shared('users', name: "user #{idx}") }
    @tags = 2.times.map { |idx| shared('tags', name: "tag #{idx}") }
    ORGS.each { |oid| seed_org(oid) }
    self
  end

  # the row keys currently in table: ids, or [call_id, tag_id] pairs for the join table
  def self.row_keys(database, table_name)
    model = database.get_model!(table_name)
    keys = model.primary_key ? model.pluck(model.primary_key) : model.pluck(*model.column_names)
    keys.sort
  end

  private

  def seed_org(oid)
    emails = 3.times.map { |idx| seed_email(oid, idx) }
    seed_recipient(oid, nil) # recipient whose email is gone (nullable email_id)
    3.times { |idx| seed_sms_message(oid, idx) }
    3.times { |idx| seed_call(oid, idx, idx.zero? ? emails.first : nil) }
  end

  def seed_email(oid, idx)
    email = owned(oid, 'emails', oid: oid, user_id: @users.first, subject: "email #{idx}")
    2.times { seed_recipient(oid, email) }
    owned(oid, 'email_attachments', email_id: email, filename: "file #{idx}") if idx < 2
    email
  end

  def seed_recipient(oid, email)
    recipient = owned(oid, 'email_recipients', oid: oid, email_id: email, address: 'a@example.com')
    owned(oid, 'email_events', email_recipient_id: recipient, name: 'delivered')
  end

  def seed_sms_message(oid, idx)
    sms = owned(oid, 'sms_messages', oid: oid, body: "sms #{idx}")
    2.times { owned(oid, 'sms_deliveries', sms_message_id: sms, status: 'sent') }
  end

  def seed_call(oid, idx, email)
    call = owned(oid, 'calls', oid: oid, user_id: @users.last, email_id: email, duration: idx)
    owned(oid, 'call_recordings', call_id: call, url: "rec #{idx}") if idx < 2
    2.times { owned(oid, 'call_notes', call_id: call, note: 'note') }
    @tags.each { |tag| seed_call_tag(oid, call, tag) }
  end

  def seed_call_tag(oid, call, tag)
    @database.get_model!('call_tags').connection.execute(
      "INSERT INTO call_tags (call_id, tag_id) VALUES (#{call}, #{tag})"
    )
    expectation(oid)['call_tags'] << [call, tag]
  end

  def shared(table_name, attributes)
    id = @database.get_model!(table_name).create!(attributes).id
    @expected_kept[table_name] << id
    id
  end

  def owned(oid, table_name, attributes)
    id = @database.get_model!(table_name).create!(attributes).id
    expectation(oid)[table_name] << id
    id
  end

  def expectation(oid)
    oid == @purge_oid ? @expected_purged : @expected_kept
  end
end
