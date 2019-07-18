# frozen_string_literal: true

module DBPurger
  # DBPurger::PurgeTableScanner scans the entire table in batches use the search_proc to determine what ids to delete
  class PurgeTableScanner
    include PurgeTableHelper

    def initialize(database, table)
      @database = database
      @table = table
      @num_deleted = 0
    end

    def model
      @model ||= @database.models.detect { |m| m.table_name == @table.name.to_s }
    end

    def purge!
      ActiveSupport::Notifications.instrument('purge.db_purger',
                                              table_name: @table.name) do |payload|
        purge_in_batches!
        purge_search_tables
        payload[:deleted] = @num_deleted
      end
      @num_deleted
    end

    private

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def purge_in_batches!
      scope = model
      scope = scope.where(@table.conditions) if @table.conditions

      instrumentation_name = 'next_batch.db_purger'
      start_instrumentation(instrumentation_name)

      scope.find_in_batches(batch_size: @table.batch_size) do |batch|
        finish_instrumentation(
          instrumentation_name,
          table_name: @table.name,
          num_records: batch.size
        )

        batch = ActiveSupport::Notifications.instrument('search_filter.db_purger',
                                                        table_name: @table.name,
                                                        num_records: batch.size) do |payload|
          records_selected = @table.search_proc.call(batch)
          payload[:num_records_selected] = records_selected.size
          records_selected
        end

        if batch.empty?
          start_instrumentation(instrumentation_name)
          next
        end

        purge_nested_tables(batch) if @table.nested_tables?
        delete_records(batch)

        start_instrumentation(instrumentation_name)
      end

      finish_instrumentation(
        instrumentation_name,
        table_name: @table.name,
        num_records: 0,
        num_selected: 0
      )
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def start_instrumentation(name)
      @instrumenter = ActiveSupport::Notifications.instrumenter
      @instrumenter.start(name, {})
    end

    def finish_instrumentation(name, payload)
      @instrumenter.finish(name, payload)
    end
  end
end
