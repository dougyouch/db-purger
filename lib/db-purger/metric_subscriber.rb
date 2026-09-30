# frozen_string_literal: true

module DBPurger
  # DBPurger::MetricSubscriber tracks the progress of the Plan#purge process
  class MetricSubscriber < ActiveSupport::Subscriber
    def self.metrics
      @metrics ||= Metrics.new
    end

    def self.reset!
      metrics.reset!
    end

    def self.finished!
      metrics.finished!
    end

    def self.auto_attach
      attach_to :db_purger
    end

    def purge(event)
      self.class.metrics.update_purge_stats(
        event.payload[:table_name],
        event.duration,
        event.payload[:deleted] || 0
      )
    end

    def delete_records(event)
      self.class.metrics.update_delete_records_stats(
        event.payload[:table_name],
        event.duration,
        event.payload[:records_deleted] || 0,
        event.payload[:num_records]
      )
    end

    def next_batch(event)
      self.class.metrics.update_lookup_stats(
        event.payload[:table_name],
        event.duration,
        event.payload[:num_records] || 0
      )
    end

    def search_filter(event)
      self.class.metrics.update_search_filter_stats(
        event.payload[:table_name],
        event.duration,
        event.payload[:num_records] || 0,
        event.payload[:num_records_selected] || 0
      )
    end
  end
end
