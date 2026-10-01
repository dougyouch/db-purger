# frozen_string_literal: true

# DBPurger is a tool to delete data from tables based on a initial purge value
module DBPurger
  autoload :AssociationGraph, 'db-purger/association_graph'
  autoload :Config, 'db-purger/config'
  autoload :DynamicPlanBuilder, 'db-purger/dynamic_plan_builder'
  autoload :Executor, 'db-purger/executor'
  autoload :Metrics, 'db-purger/metrics'
  autoload :MetricSubscriber, 'db-purger/metric_subscriber'
  autoload :PurgeTable, 'db-purger/purge_table'
  autoload :PurgeTableHelper, 'db-purger/purge_table_helper'
  autoload :PurgeTableScanner, 'db-purger/purge_table_scanner'
  autoload :Plan, 'db-purger/plan'
  autoload :PlanBuilder, 'db-purger/plan_builder'
  autoload :PlanValidator, 'db-purger/plan_validator'
  autoload :PlanWriter, 'db-purger/plan_writer'
  autoload :Table, 'db-purger/table'

  # The config in effect for the current thread: the one set by with_config, else the global default
  def self.config
    Thread.current[:db_purger_config] || default_config
  end

  def self.default_config
    @default_config ||= Config.new
  end

  # Runs the block with config in effect for this thread only, so concurrent or
  # later executors can't change explain mode out from under a running purge
  def self.with_config(config)
    previous = Thread.current[:db_purger_config]
    Thread.current[:db_purger_config] = config
    yield
  ensure
    Thread.current[:db_purger_config] = previous
  end
end
