# frozen_string_literal: true

require "tmpdir"
require "socket"

RSpec.describe EmbeddingUtil::ServerManager do
  let(:config) do
    EmbeddingUtil::Configuration.new.tap do |item|
      item.state_dir = Dir.mktmpdir("embedding-util-spec")
      item.timeout = 0.1
      item.startup_timeout = 0.1
    end
  end
  let(:manager) { described_class.new(config: config) }
  let(:model) { EmbeddingUtil::ServerModel.parse("embedding-small_multilingual_v1") }

  after do
    FileUtils.rm_rf(config.state_dir)
  end

  it "uses existing healthy state without starting a new server" do
    manager.send(:write_state, model, pid: Process.pid, url: "http://127.0.0.1:18080", runtime: "test", port: 18_080)
    allow(manager).to receive(:healthy_url?).and_return(true)
    allow(manager).to receive(:start_background)

    expect(manager.ensure_server(:embedding)).to eq("http://127.0.0.1:18080")
    expect(manager).not_to have_received(:start_background)
  end

  it "starts a background serve process when state is missing" do
    allow(manager).to receive(:start_background) do
      manager.send(:write_state, model, pid: Process.pid, url: "http://127.0.0.1:18080", runtime: "test", port: 18_080)
    end
    allow(manager).to receive(:healthy_url?).and_return(true)

    expect(manager.ensure_server(:embedding)).to eq("http://127.0.0.1:18080")
    expect(manager).to have_received(:start_background).with(model)
  end

  it "reports missing processes as unhealthy" do
    state = { "pid" => -1, "url" => "http://127.0.0.1:18080" }

    expect(manager.send(:healthy_state?, state)).to be(false)
  end

  it "includes the startup log tail when startup times out" do
    log_path = File.join(config.state_dir, "embedding-small_multilingual_v1.log")
    File.write(log_path, "Downloading model\nStill downloading\n")

    message = manager.send(:startup_timeout_message, model, log_path)

    expect(message).to include("timed out after 0.1s")
    expect(message).to include(log_path)
    expect(message).to include("Still downloading")
  end

  it "selects the next free port when the default is occupied" do
    server = TCPServer.new("127.0.0.1", 0)
    occupied_port = server.addr[1]
    config.embedding_port = occupied_port

    selected_port = manager.send(:selected_port_for, model, host: "127.0.0.1")

    expect(selected_port).to be > occupied_port
  ensure
    server&.close
  end

  it "raises immediately when an explicit port is occupied" do
    server = TCPServer.new("127.0.0.1", 0)
    occupied_port = server.addr[1]

    expect do
      manager.send(:selected_port_for, model, host: "127.0.0.1", port: occupied_port)
    end.to raise_error(EmbeddingUtil::UnsupportedProviderError, /port 127\.0\.0\.1:#{occupied_port} is already in use/)
  ensure
    server&.close
  end
end
