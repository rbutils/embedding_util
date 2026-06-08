# frozen_string_literal: true

RSpec.describe EmbeddingUtil do
  it "has a version number" do
    expect(EmbeddingUtil::VERSION).not_to be_nil
  end

  it "exposes the stable small multilingual profile" do
    profile = described_class.profile(:small_multilingual_v1)

    expect(profile.embedding.fetch(:repo)).to eq("Qwen/Qwen3-Embedding-0.6B-GGUF")
    expect(profile.embedding.fetch(:file)).to eq("Qwen3-Embedding-0.6B-Q8_0.gguf")
    expect(profile.embedding.fetch(:dimensions)).to eq(1024)
    expect(profile.embedding.fetch(:server_flags)).to eq(["--embedding", "--pooling", "last"])
    expect(profile.reranker.fetch(:repo)).to eq("ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF")
    expect(profile.reranker.fetch(:server_flags)).to eq(["--reranking"])
  end

  it "reports endpoint support only when an endpoint is configured" do
    expected_support = [{
      provider: :endpoint,
      supported: false,
      embedding_endpoint: nil,
      reranker_endpoint: nil
    }]

    expect(described_class.support).to eq(expected_support)

    described_class.configure { |config| config.embedding_endpoint = "http://127.0.0.1:18080" }

    expect(described_class.support.first).to include(provider: :endpoint, supported: true, embedding_endpoint: "http://127.0.0.1:18080")
  end

  it "raises an actionable error when no provider is configured" do
    expect { described_class.embed("hello") }.to raise_error(EmbeddingUtil::UnsupportedProviderError, /configure already-running local endpoints/)
  end
end
