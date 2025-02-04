RSpec.describe Airbrake::Config do
  subject(:config) { described_class.new }

  let(:resolved_promise) { Airbrake::Promise.new.resolve }
  let(:rejected_promise) { Airbrake::Promise.new.reject }

  let(:valid_params) { { project_id: 1, project_key: '2' } }

  its(:project_id) { is_expected.to be_nil }
  its(:project_key) { is_expected.to be_nil }
  its(:logger) { is_expected.to be_a(Logger) }
  its(:app_version) { is_expected.to be_nil }
  its(:versions) { is_expected.to be_empty }
  its(:host) { is_expected.to eq('https://api.airbrake.io') }
  its(:error_host) { is_expected.to eq('https://api.airbrake.io') }
  its(:apm_host) { is_expected.to eq('https://api.airbrake.io') }
  its(:error_endpoint) { is_expected.not_to be_nil }
  its(:workers) { is_expected.to eq(1) }
  its(:queue_size) { is_expected.to eq(100) }
  its(:root_directory) { is_expected.to eq(Bundler.root.realpath.to_s) }
  its(:environment) { is_expected.to be_nil }
  its(:ignore_environments) { is_expected.to be_empty }
  its(:timeout) { is_expected.to be_nil }
  its(:blocklist_keys) { is_expected.to be_empty }
  its(:allowlist_keys) { is_expected.to be_empty }
  its(:performance_stats) { is_expected.to be(true) }
  its(:performance_stats_flush_period) { is_expected.to eq(15) }
  its(:query_stats) { is_expected.to be(true) }
  its(:job_stats) { is_expected.to be(true) }
  its(:error_notifications) { is_expected.to be(true) }
  its(:remote_config) { is_expected.to be(true) }
  its(:backlog) { is_expected.to be(true) }

  its(:remote_config_host) do
    is_expected.to eq('https://notifier-configs.airbrake.io')
  end

  describe "#new" do
    context "when user config is passed" do
      subject { described_class.new(logger: StringIO.new) }

      its(:logger) { is_expected.to be_a(StringIO) }
    end
  end

  describe "#valid?" do
    context "when the config is valid" do
      before do
        config.project_id = 123
        config.project_key = 'abc'
      end

      it { is_expected.to be_valid }
    end

    context "when the config is invalid" do
      it { is_expected.not_to be_valid }
    end
  end

  describe "#ignored_environment?" do
    context "when Validator returns a resolved promise" do
      before do
        allow(Airbrake::Config::Validator).to receive(:check_notify_ability)
          .and_return(resolved_promise)
      end

      its(:ignored_environment?) { is_expected.to be_falsey }
    end

    context "when Validator returns a rejected promise" do
      before do
        allow(Airbrake::Config::Validator).to receive(:check_notify_ability)
          .and_return(rejected_promise)
      end

      its(:ignored_environment?) { is_expected.to be_truthy }
    end
  end

  describe "#error_endpoint" do
    subject { described_class.new(valid_params.merge(user_config)) }

    context "when host ends with a URL with a slug with a trailing slash" do
      let(:user_config) { { host: 'https://localhost/bingo/' } }

      its(:error_endpoint) do
        is_expected.to eq(URI('https://localhost/bingo/api/v3/projects/1/notices'))
      end
    end

    context "when host ends with a URL with a slug without a trailing slash" do
      let(:user_config) { { host: 'https://localhost/bingo' } }

      its(:error_endpoint) do
        is_expected.to eq(URI('https://localhost/api/v3/projects/1/notices'))
      end
    end
  end

  describe "#validate" do
    its(:validate) { is_expected.to be_an(Airbrake::Promise) }
  end

  describe "#check_configuration" do
    subject { described_class.new(valid_params.merge(user_config)) }

    let(:user_config) { {} }

    its(:check_configuration) { is_expected.to be_an(Airbrake::Promise) }

    context "when config is invalid" do
      let(:user_config) { { project_id: nil } }

      its(:check_configuration) { is_expected.to be_rejected }
    end

    context "when current environment is ignored" do
      let(:user_config) { { environment: 'test', ignore_environments: ['test'] } }

      its(:check_configuration) { is_expected.to be_rejected }
    end

    context "when config is valid and allows notifying" do
      its(:check_configuration) { is_expected.not_to be_rejected }
    end
  end

  describe "#check_performance_options" do
    it "returns a promise" do
      metric = Airbrake::Query.new(method: '', route: '', query: '', timing: 1)
      expect(config.check_performance_options(metric))
        .to be_an(Airbrake::Promise)
    end

    context "when performance stats are disabled" do
      before { config.performance_stats = false }

      let(:metric) do
        Airbrake::Request.new(
          method: 'GET', route: '/foo', status_code: 200, timing: 1,
        )
      end

      it "returns a rejected promise" do
        promise = config.check_performance_options(metric)
        expect(promise.value).to eq(
          'error' => "The Performance Stats feature is disabled",
        )
      end
    end

    context "when query stats are disabled" do
      before { config.query_stats = false }

      let(:metric) do
        Airbrake::Query.new(method: 'GET', route: '/foo', query: '', timing: 1)
      end

      it "returns a rejected promise" do
        promise = config.check_performance_options(metric)
        expect(promise.value).to eq(
          'error' => "The Query Stats feature is disabled",
        )
      end
    end

    context "when job stats are disabled" do
      before { config.job_stats = false }

      let(:metric) do
        Airbrake::Queue.new(queue: 'foo_queue', error_count: 0, timing: 1)
      end

      it "returns a rejected promise" do
        promise = config.check_performance_options(metric)
        expect(promise.value).to eq(
          'error' => "The Job Stats feature is disabled",
        )
      end
    end
  end

  describe "#logger" do
    it "sets logger level to Logger::WARN" do
      expect(config.logger.level).to eq(Logger::WARN)
    end
  end
end
