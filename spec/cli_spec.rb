# frozen_string_literal: true

require "stringio"

RSpec.describe EmbeddingUtil::CLI do
  def capture_stdout
    previous = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous
  end

  it "lists profiles" do
    output = capture_stdout { described_class.start(["profiles"]) }

    expect(output).to include("small_multilingual_v1")
    expect(output).to include("Qwen/Qwen3-Embedding-0.6B-GGUF")
    expect(output).to include("ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF")
  end

  it "prints endpoint support" do
    output = capture_stdout do
      described_class.start([
                              "support",
                              "--embedding-endpoint", "http://127.0.0.1:18080",
                              "--reranker-endpoint", "http://127.0.0.1:18081"
                            ])
    end

    expect(output).to include("endpoint: supported")
    expect(output).to include("embedding_endpoint: http://127.0.0.1:18080")
    expect(output).to include("reranker_endpoint: http://127.0.0.1:18081")
  end

  it "does not apply idle shutdown to explicit serve by default" do
    manager = instance_double(EmbeddingUtil::ServerManager)
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow(manager).to receive(:serve)

    described_class.start(["serve", "--model", "embedding-small_multilingual_v1"])

    expect(manager).to have_received(:serve).with(
      model: "embedding-small_multilingual_v1",
      runtime: :auto,
      shutdown_idle: nil,
      host: "127.0.0.1",
      port: nil
    )
  end

  it "does not override environment-derived configuration with CLI defaults" do
    previous_runtime = ENV["EMBEDDING_UTIL_RUNTIME"]
    previous_startup_timeout = ENV["EMBEDDING_UTIL_STARTUP_TIMEOUT"]
    ENV["EMBEDDING_UTIL_RUNTIME"] = "llama_server"
    ENV["EMBEDDING_UTIL_STARTUP_TIMEOUT"] = "12"
    EmbeddingUtil.reset_configuration!

    capture_stdout { described_class.start(["support"]) }

    expect(EmbeddingUtil.configuration.runtime).to eq(:llama_server)
    expect(EmbeddingUtil.configuration.startup_timeout).to eq(12.0)
  ensure
    ENV["EMBEDDING_UTIL_RUNTIME"] = previous_runtime
    ENV["EMBEDDING_UTIL_STARTUP_TIMEOUT"] = previous_startup_timeout
  end
end
