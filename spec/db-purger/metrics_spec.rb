# frozen_string_literal: true

require 'spec_helper'

describe DBPurger::Metrics do
  let(:metrics) { DBPurger::Metrics.new }

  describe '#elapsed_time_in_seconds' do
    it 'measures up to now while running and up to finished! afterwards' do
      allow(Time).to receive(:now).and_return(Time.at(100))
      metrics.reset!

      allow(Time).to receive(:now).and_return(Time.at(103))
      expect(metrics.elapsed_time_in_seconds).to eq(3)

      allow(Time).to receive(:now).and_return(Time.at(105))
      metrics.finished!
      allow(Time).to receive(:now).and_return(Time.at(200))
      expect(metrics.elapsed_time_in_seconds).to eq(5)
    end
  end

  describe '#as_json' do
    it 'reports the stats gathered during a purge' do
      create(:company, id: 1).tap { |company| create(:employment, company: company) }
      plan = DBPurger::PlanBuilder.build do
        base_table(:companies, :id)
        child_table(:employments, :company_id)
      end
      plan.purge!(DYNAMIC_DATABASE, 1)

      json = DBPurger::MetricSubscriber.metrics.as_json
      expect(json.keys).to eq(%i[took started_at finished_at purge_stats delete_stats nullify_stats lookup_stats
                                 filter_stats])
      expect(json[:took]).to be >= 0
      expect(json[:finished_at]).to be >= json[:started_at]
      expect(json[:delete_stats][:employments][:num_deleted]).to eq(1)
      expect(json[:delete_stats][:companies][:num_deleted]).to eq(1)
    end
  end
end
