# frozen_string_literal: true

RSpec.describe EmbeddingUtil::RuntimeCommand do
  let(:embedding_model) { EmbeddingUtil::ServerModel.parse("embedding-small_multilingual_v1") }
  let(:reranker_model) { EmbeddingUtil::ServerModel.parse("reranker-small_multilingual_v1") }

  it "builds ramalama commands with pinned Hugging Face models and runtime args" do
    command = described_class.new(runtime: :ramalama, server_model: embedding_model, host: "127.0.0.1", port: 18_080)
    expected = [
      "ramalama", "--runtime=llama.cpp", "serve",
      "--name", "embedding-util-embedding-small-multilingual-v1",
      "--ctx-size", "4096",
      "--host", "127.0.0.1",
      "--port", "18080",
      "--runtime-args=--embedding --pooling last --cache-ram 0",
      "hf://Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
    ]

    expect(command.argv).to eq(expected)
  end

  it "passes an explicit Ramalama device option" do
    command = described_class.new(runtime: :ramalama, server_model: embedding_model, host: "127.0.0.1", port: 18_080, ramalama_device: "none")

    expect(command.argv).to include("--device", "none")
  end

  it "builds Ramalama stop commands for named detached servers" do
    allow(described_class).to receive(:command_path).and_call_original
    allow(described_class).to receive(:command_path).with("ramalama").and_return("/usr/bin/ramalama")
    allow(described_class).to receive(:command_path).with("podman").and_return("/usr/bin/podman")
    allow(described_class).to receive(:command_path).with("docker").and_return(nil)
    command = described_class.new(runtime: :ramalama, server_model: embedding_model, host: "127.0.0.1", port: 18_080)

    expect(command).to be_detached_server
    expect(command.stop_argv).to eq(%w[ramalama stop embedding-util-embedding-small-multilingual-v1])
    expected_stop_argvs = [
      %w[ramalama stop embedding-util-embedding-small-multilingual-v1],
      %w[podman stop --time 0 embedding-util-embedding-small-multilingual-v1]
    ]
    expect(command.stop_argvs).to eq(expected_stop_argvs)
  end

  it "builds llama-server commands with profile flags" do
    command = described_class.new(runtime: :llama_server, server_model: reranker_model, host: "127.0.0.1", port: 18_081)
    expected = [
      "llama-server",
      "--host", "127.0.0.1",
      "--port", "18081",
      "-hf", "ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF",
      "-hff", "qwen3-reranker-0.6b-q8_0.gguf",
      "--reranking", "--batch-size", "1024", "--ubatch-size", "1024"
    ]

    expect(command.argv).to eq(expected)
  end

  it "normalizes hyphenated runtime names" do
    allow(described_class).to receive(:command_path).with("llama-server").and_return("/usr/bin/llama-server")

    expect(described_class.normalize_runtime("llama-server")).to eq(:llama_server)
    expect(described_class.available?("llama-server")).to be(true)
  end
end
