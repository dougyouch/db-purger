# frozen_string_literal: true

# DBPurger is a tool to delete data from tables based on a initial purge value
module DBPurger
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
  autoload :Table, 'db-purger/table'

  def self.config
    @config ||= Config.new
  end
end
