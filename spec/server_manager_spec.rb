# frozen_string_literal: true

require "tmpdir"
require "socket"
require "stringio"

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

  it "does not return a stale URL when the tracked process exits after lock release" do
    manager.send(:write_state, model, pid: Process.pid, url: "http://127.0.0.1:18080", runtime: "test", port: 18_080)
    allow(manager).to receive(:process_running?).and_return(true, false, false)
    allow(manager).to receive(:healthy_url?).and_return(true)
    allow(manager).to receive(:start_background)

    expect do
      manager.ensure_server(:embedding)
    end.to raise_error(EmbeddingUtil::UnsupportedProviderError, /server process exited before becoming healthy/)
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

  it "waits outside the startup lock when another process is already starting" do
    manager.send(:write_state, model, pid: Process.pid, url: "http://127.0.0.1:18080", runtime: "starting", port: 18_080)
    allow(manager).to receive(:start_background)
    allow(manager).to receive(:healthy_url?).and_return(false, true)

    expect(manager.ensure_server(:embedding)).to eq("http://127.0.0.1:18080")
    expect(manager).not_to have_received(:start_background)
  end

  it "omits shutdown-idle from background argv when idle shutdown is nil" do
    config.shutdown_idle = nil
    allow(manager).to receive(:selected_port_for).and_return(18_080)
    allow(Process).to receive(:spawn).and_return(12_345)
    allow(Process).to receive(:detach)

    manager.send(:start_background, model)

    expect(Process).to have_received(:spawn) do |*args|
      expect(args).not_to include("--shutdown-idle")
    end
  end

  it "passes reranker ubatch settings to background serve processes" do
    config.reranker_ubatch_size = 4096
    allow(manager).to receive(:selected_port_for).and_return(18_081)
    allow(Process).to receive(:spawn).and_return(12_345)
    allow(Process).to receive(:detach)
    reranker = EmbeddingUtil::ServerModel.parse("reranker-small_multilingual_v1")

    manager.send(:start_background, reranker)

    expect(Process).to have_received(:spawn) do |*args|
      expect(args).to include("--reranker-ubatch-size", "4096")
      expect(args).to include("--reranker-max-ubatch-size", "4096")
    end
  end

  it "applies configured reranker ubatch size to runtime flags" do
    config.reranker_ubatch_size = 4096
    reranker = EmbeddingUtil::ServerModel.parse("reranker-small_multilingual_v1")

    flags = manager.send(:server_flags, reranker)

    expect(flags).to eq(["--reranking", "--ubatch-size", "4096"])
  end

  it "writes provisional state when starting a background process" do
    allow(manager).to receive(:selected_port_for).and_return(18_080)
    allow(Process).to receive(:spawn).and_return(12_345)
    allow(Process).to receive(:detach)

    manager.send(:start_background, model)
    state = manager.send(:read_state, model)

    expect(state).to include("pid" => 12_345, "runtime" => "starting", "url" => "http://127.0.0.1:18080")
  end

  it "does not kill a process again when it exits after TERM" do
    allow(Process).to receive(:kill)
    allow(manager).to receive(:sleep)
    allow(manager).to receive(:process_running?).and_return(false)

    manager.send(:terminate_idle_process, 12_345)

    expect(Process).to have_received(:kill).with("TERM", 12_345).once
    expect(Process).not_to have_received(:kill).with("KILL", 12_345)
  end

  it "terminates non-detached runtime processes during cleanup" do
    command = instance_double(EmbeddingUtil::RuntimeCommand, detached_server?: false)
    allow(manager).to receive(:process_running?).and_return(true, false)
    allow(manager).to receive(:terminate_idle_process)

    manager.send(:terminate_runtime_process, command, 12_345)

    expect(manager).to have_received(:terminate_idle_process).with(12_345)
  end

  it "does not terminate detached runtime launcher pids during cleanup" do
    command = instance_double(EmbeddingUtil::RuntimeCommand, detached_server?: true)
    allow(manager).to receive(:terminate_idle_process)

    manager.send(:terminate_runtime_process, command, 12_345)

    expect(manager).not_to have_received(:terminate_idle_process)
  end

  it "does not terminate the current process when specs stub wait thread pids" do
    command = instance_double(EmbeddingUtil::RuntimeCommand, detached_server?: false)
    allow(manager).to receive(:terminate_idle_process)

    manager.send(:terminate_runtime_process, command, Process.pid)

    expect(manager).not_to have_received(:terminate_idle_process)
  end

  it "starts the idle watchdog only after the server is healthy" do
    events = []
    wait_thread = double("wait_thread", pid: Process.pid, value: instance_double(Process::Status, exitstatus: 0))
    allow(Open3).to receive(:popen2e).and_yield(nil, StringIO.new, wait_thread)
    allow(manager).to receive(:selected_port_for).and_return(18_080)
    allow(manager).to receive(:wait_for_serving) { events << :healthy }
    allow(manager).to receive(:start_watchdog) do
      events << :watchdog
      double("watchdog", kill: nil)
    end

    manager.serve(model: model, runtime: :llama_server, shutdown_idle: 5)

    expect(events).to eq(%i[healthy watchdog])
  end

  it "does not consider idle shutdown while waiting for startup health" do
    allow(manager).to receive(:healthy_url?).and_return(false)
    allow(manager).to receive(:process_running?).and_return(false)

    expect do
      manager.send(:wait_for_serving, model, "http://127.0.0.1:18080", 12_345)
    end.to raise_error(EmbeddingUtil::UnsupportedProviderError, /server process exited before becoming healthy/)
  end

  it "allows detached launchers to exit before the named server becomes healthy" do
    allow(manager).to receive(:healthy_url?).and_return(false, true)
    allow(manager).to receive(:process_running?).and_return(false)

    expect do
      manager.send(:wait_for_serving, model, "http://127.0.0.1:18080", 12_345, check_process: false)
    end.not_to raise_error
  end

  it "stops detached Ramalama servers after stdout is idle" do
    command = instance_double(EmbeddingUtil::RuntimeCommand)
    allow(manager).to receive(:sleep)
    allow(manager).to receive(:stop_detached_server)

    expect(manager.send(:supervise_detached_server, command, 5) { Time.now - 6 }).to eq(0)
    expect(manager).to have_received(:stop_detached_server).with(command)
  end

  it "tries fallback stop commands for detached servers" do
    command = instance_double(
      EmbeddingUtil::RuntimeCommand,
      stop_argvs: [%w[ramalama stop model], %w[podman stop --time 0 model]]
    )
    allow(manager).to receive(:system).and_return(false, true)

    manager.send(:stop_detached_server, command)

    expect(manager).to have_received(:system).with("ramalama", "stop", "model", out: File::NULL, err: File::NULL).ordered
    expect(manager).to have_received(:system).with("podman", "stop", "--time", "0", "model", out: File::NULL, err: File::NULL).ordered
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
