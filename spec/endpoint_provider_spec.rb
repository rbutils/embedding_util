# frozen_string_literal: true

RSpec.describe EmbeddingUtil::Providers::Endpoint do
  let(:provider) { described_class.new(config: EmbeddingUtil.configuration) }

  before do
    EmbeddingUtil.configure do |config|
      config.embedding_endpoint = "http://embedding.example"
      config.reranker_endpoint = "http://reranker.example"
    end
  end

  it "returns one embedding result for a single input" do
    allow(provider).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }],
      "usage" => { "total_tokens" => 2 }
    )

    result = provider.embed(["hello"])

    expect(result.embedding).to eq([0.1, 0.2])
    expect(result.model).to eq("qwen3-embedding-0.6b")
    expect(result.profile).to eq(:small_multilingual_v1)
    expect(result.provider).to eq(:endpoint)
    expect(result.metadata).to eq(usage: { "total_tokens" => 2 })
  end

  it "returns ranked documents with original indices and scores" do
    allow(provider).to receive(:post_json).and_return(
      "model" => "qwen3-reranker-0.6b",
      "results" => [
        { "index" => 1, "relevance_score" => 0.9 },
        { "index" => 0, "relevance_score" => 0.1 }
      ],
      "usage" => { "total_tokens" => 12 }
    )

    result = provider.rerank("query", %w[first second])

    expect(result.results.map(&:document)).to eq(%w[second first])
    expect(result.results.map(&:index)).to eq([1, 0])
    expect(result.results.map(&:score)).to eq([0.9, 0.1])
    expect(result.metadata).to eq(usage: { "total_tokens" => 12 })
  end
end
