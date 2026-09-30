# frozen_string_literal: true

module DBPurger
  # DBPurger::Config keeps track of global config options for the purge process
  class Config
    DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'

    attr_writer :explain_file,
                :datetime_format

    def initialize(options = {})
      self.explain = options[:explain]
      @explain_file = options[:explain_file]
      @datetime_format = options[:datetime_format]
    end

    # Fail closed: a value like 'true' must not silently mean "run for real"
    def explain=(value)
      unless [true, false, nil].include?(value)
        raise(ArgumentError, "explain must be true, false or nil, got #{value.inspect}")
      end

      @explain = value
    end

    def explain?
      @explain == true
    end

    def explain_file
      @explain_file || $stdout
    end

    def datetime_format
      @datetime_format || DEFAULT_DATETIME_FORMAT
    end
  end
end
