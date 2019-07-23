# frozen_string_literal: true

module DBPurger
  # DBPurger::Metrics keeps track of each part of the purge process
  class Metrics
    attr_reader :started_at,
                :finished_at,
                :purge_stats,
                :delete_stats,
                :lookup_stats,
                :filter_stats

    def initialize
      reset!
    end

    def reset!
      @started_at = Time.now
      @purge_stats = {}
      @delete_stats = {}
      @lookup_stats = {}
      @filter_stats = {}
      @finished_at = nil
    end

    def finished!
      @finished_at = Time.now
    end

    def elapsed_time_in_seconds
      (@finished_at || Time.now) - @started_at
    end

    def update_purge_stats(table_name, duration, num_records)
      stats = (@purge_stats[table_name] ||= Hash.new(0))
      stats[:duration] += duration
      stats[:num_purges] += 1
      stats[:num_records] += num_records
      stats
    end

    def update_delete_records_stats(table_name, duration, num_deleted, num_expected_to_delete = nil)
      stats = (@delete_stats[table_name] ||= Hash.new(0))
      stats[:duration] += duration
      stats[:num_delete_queries] += 1
      stats[:num_deleted] += num_deleted
      stats[:num_expected_to_delete] += num_expected_to_delete if num_expected_to_delete
      stats
    end

    def update_lookup_stats(table_name, duration, records_found)
      stats = (@lookup_stats[table_name] ||= Hash.new(0))
      stats[:duration] += duration
      stats[:num_lookups] += 1
      stats[:records_found] += records_found
      stats
    end

    def update_search_filter_stats(table_name, duration, records_found, records_selected)
      stats = (@filter_stats[table_name] ||= Hash.new(0))
      stats[:duration] += duration
      stats[:num_lookups] += 1
      stats[:records_found] += records_found
      stats[:records_selected] += records_selected
      stats
    end

    def as_json(_opts = {})
      {
        took: elapsed_time_in_seconds,
        started_at: @started_at,
        finished_at: @finished_at,
        purge_stats: @purge_stats,
        delete_stats: @delete_stats,
        lookup_stats: @lookup_stats,
        filter_stats: @filter_stats
      }
    end
  end
end
