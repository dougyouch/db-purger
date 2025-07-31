# frozen_string_literal: true

require 'rubygems'
require 'bundler'
require 'securerandom'
require 'active_record'
require 'simplecov'

SimpleCov.start

begin
  Bundler.require(:default, :spec)
rescue Bundler::BundlerError => e
  warn e.message
  warn 'Run `bundle install` to install missing gems'
  exit e.status_code
end

$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
$LOAD_PATH.unshift(__dir__)
require 'db-purger'

require 'support/test_db'

module DBPurger
  class TestSubscriber < ActiveSupport::Subscriber
    def self.tables
      @tables ||= {}
    end

    def tables
      self.class.tables
    end

    def purge(event)
      tables[event.payload[:table_name]] ||= {}
      tables[event.payload[:table_name]][:deleted] = event.payload[:deleted]
    end

    def delete_records(event)
      tables[event.payload[:table_name]] ||= {}
      tables[event.payload[:table_name]][:records_deleted] = event.payload[:records_deleted]
    end

    def next_batch(event)
      tables[event.payload[:table_name]] ||= {}
      tables[event.payload[:table_name]][:num_records] = event.payload[:num_records]
    end
  end
end
DBPurger::TestSubscriber.attach_to :db_purger
DBPurger::MetricSubscriber.auto_attach

# ActiveRecord::Base.logger = Logger.new(STDOUT)

require 'factories/test_factory'
require 'database_cleaner'
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.include FactoryBot::Syntax::Methods
end
