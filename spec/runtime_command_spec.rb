# frozen_string_literal: true

RSpec.describe EmbeddingUtil::RuntimeCommand do
  let(:embedding_model) { EmbeddingUtil::ServerModel.parse("embedding-small_multilingual_v1") }
  let(:reranker_model) { EmbeddingUtil::ServerModel.parse("reranker-small_multilingual_v1") }

  it "builds ramalama commands with pinned Hugging Face models and runtime args" do
    command = described_class.new(runtime: :ramalama, server_model: embedding_model, host: "127.0.0.1", port: 18_080)
    expected = [
      "ramalama", "--runtime=llama.cpp", "serve",
      "--host", "127.0.0.1",
      "--port", "18080",
      "--runtime-args=--embedding --pooling last",
      "hf://Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
    ]

    expect(command.argv).to eq(expected)
  end

  it "builds llama-server commands with profile flags" do
    command = described_class.new(runtime: :llama_server, server_model: reranker_model, host: "127.0.0.1", port: 18_081)
    expected = [
      "llama-server",
      "--host", "127.0.0.1",
      "--port", "18081",
      "-hf", "ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF",
      "-hff", "qwen3-reranker-0.6b-q8_0.gguf",
      "--reranking"
    ]

    expect(command.argv).to eq(expected)
  end

  it "normalizes hyphenated runtime names" do
    allow(described_class).to receive(:command_path).with("llama-server").and_return("/usr/bin/llama-server")

    expect(described_class.normalize_runtime("llama-server")).to eq(:llama_server)
    expect(described_class.available?("llama-server")).to be(true)
  end
end
