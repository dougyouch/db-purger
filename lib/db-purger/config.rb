# frozen_string_literal: true

module DBPurger
  # DBPurger::Config keeps track of global config options for the purge process
  class Config
    attr_writer :explain,
                :explain_file

    def explain?
      @explain == true
    end

    def explain_file
      (@explain_file || $stdout)
    end
  end
end
