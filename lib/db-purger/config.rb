# frozen_string_literal: true

module DBPurger
  # DBPurger::Config keeps track of global config options for the purge process
  class Config
    DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'

    attr_writer :explain,
                :explain_file,
                :datetime_format

    def explain?
      @explain == true
    end

    def explain_file
      (@explain_file || $stdout)
    end

    def datetime_format
      @datetime_format || DEFAULT_DATETIME_FORMAT
    end
  end
end
