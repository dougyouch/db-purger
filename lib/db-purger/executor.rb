# frozen_string_literal: true

module DBPurger
  # DBPurger::Executor used to execute a purge plan with verification
  class Executor
    attr_writer :error_io

    def initialize(database, plan, options = {})
      @database = database
      @plan = plan.is_a?(Plan) ? plan : load_plan(plan)
      setup_config(options)
      @error_io = $stderr
    end

    def purge!(purge_value)
      raise('purge_value is nil') if purge_value.nil?

      @plan.purge!(@database, purge_value)
    end

    def verify!
      return if plan_validator.valid?

      output_plan_errors
      raise('purge plan failed verification')
    end

    private

    def plan_validator
      @plan_validator ||= PlanValidator.new(@database, @plan)
    end

    def setup_config(options)
      ::DBPurger.config.explain = options[:explain]
      ::DBPurger.config.explain_file = options[:explain_file]
      ::DBPurger.config.datetime_format = options[:datetime_format]
    end

    def load_plan(file)
      PlanBuilder
        .new(Plan.new)
        .load_plan_file(file)
    end

    def output_plan_errors
      plan_validator.errors.each do |error|
        @error_io.puts "#{error.attribute}: #{error.type}"
      end
    end
  end
end
