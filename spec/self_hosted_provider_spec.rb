# frozen_string_literal: true

RSpec.describe EmbeddingUtil::Providers::SelfHosted do
  let(:provider) { described_class.new(config: EmbeddingUtil.configuration) }

  it "uses a self-hosted embedding endpoint after ensuring the server" do
    manager = instance_double(EmbeddingUtil::ServerManager, ensure_server: "http://127.0.0.1:18080")
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }]
    )

    result = provider.embed(["hello"])

    expect(result.embedding).to eq([[0.1, 0.2]])
    expect(manager).to have_received(:ensure_server).with(:embedding, profile: EmbeddingUtil.profile)
  end

  it "uses a self-hosted reranker endpoint after ensuring the server" do
    manager = instance_double(EmbeddingUtil::ServerManager, ensure_server: "http://127.0.0.1:18081")
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-reranker-0.6b",
      "results" => [{ "index" => 0, "relevance_score" => 0.8 }]
    )

    result = provider.rerank("query", ["document"])

    expect(result.results.first.score).to eq(0.8)
    expect(manager).to have_received(:ensure_server).with(:reranker, profile: EmbeddingUtil.profile)
  end
end
