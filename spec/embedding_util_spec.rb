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

  it "defaults to a first-run friendly startup timeout" do
    expect(described_class.configuration.startup_timeout).to eq(3600)
  end

  it "reports endpoint support only when an endpoint is configured" do
    endpoint_support = described_class.support.find { |item| item.fetch(:provider) == :endpoint }

    expect(endpoint_support).to eq({
                                     provider: :endpoint,
                                     supported: false,
                                     embedding_endpoint: nil,
                                     reranker_endpoint: nil
                                   })

    described_class.configure { |config| config.embedding_endpoint = "http://127.0.0.1:18080" }

    endpoint_support = described_class.support.find { |item| item.fetch(:provider) == :endpoint }
    expect(endpoint_support).to include(provider: :endpoint, supported: true, embedding_endpoint: "http://127.0.0.1:18080")
  end

  it "raises an actionable error when no provider is configured" do
    allow(EmbeddingUtil::ServerManager).to receive(:supported?).and_return(false)

    expect { described_class.embed("hello") }.to raise_error(EmbeddingUtil::UnsupportedProviderError, /Configure already-running local endpoints/)
  end

  it "returns a flat vector for embed and nested vectors for embed_many" do
    described_class.configure { |config| config.embedding_endpoint = "http://embedding.example" }
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }]
    )

    expect(described_class.embed("hello", provider: :endpoint)).to eq([0.1, 0.2])
    expect(described_class.embed_many(["hello"], provider: :endpoint)).to eq([[0.1, 0.2]])
  end

  it "does not mutate global configuration when selecting an explicit provider" do
    described_class.configure { |config| config.embedding_endpoint = "http://embedding.example" }
    previous_provider = described_class.configuration.provider
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }]
    )

    described_class.embed("hello", provider: :endpoint)

    expect(described_class.configuration.provider).to eq(previous_provider)
  end
end
