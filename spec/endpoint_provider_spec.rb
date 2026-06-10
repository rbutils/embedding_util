# frozen_string_literal: true

RSpec.describe EmbeddingUtil::Providers::Endpoint do
  let(:provider) { described_class.new(config: EmbeddingUtil.configuration) }

  before do
    EmbeddingUtil.configure do |config|
      config.embedding_endpoint = "http://embedding.example"
      config.reranker_endpoint = "http://reranker.example"
    end
  end

  it "returns embedding results as one vector per input" do
    allow(provider).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }],
      "usage" => { "total_tokens" => 2 }
    )

    result = provider.embed(["hello"])

    expect(result.embedding).to eq([[0.1, 0.2]])
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

  it "preserves endpoint base paths when adding API paths" do
    uri = provider.send(:endpoint_uri, "http://example.test/prefix/api", "/v1/embeddings")

    expect(uri.to_s).to eq("http://example.test/prefix/api/v1/embeddings")
  end

  it "does not treat JSON 404 responses as endpoint-not-found fallbacks" do
    response = Struct.new(:code, :body) do
      def is_a?(klass)
        return false if klass == Net::HTTPSuccess

        super
      end
    end.new("404", '{"error":"model not found"}')
    allow(Net::HTTP).to receive(:start).and_return(response)

    expect do
      provider.send(:post_json, "http://reranker.example", "/v1/rerank", {})
    end.to raise_error(EmbeddingUtil::EndpointError, /model not found/)
  end

  it "wraps network failures in endpoint errors" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED.new("connection refused"))

    expect do
      provider.send(:post_json, "http://embedding.example", "/v1/embeddings", {})
    end.to raise_error(EmbeddingUtil::EndpointError, %r{could not reach http://embedding\.example/v1/embeddings})
  end

  it "adds a reranker batch-size hint for llama.cpp physical batch failures" do
    response = Struct.new(:code, :body) do
      def is_a?(klass)
        return false if klass == Net::HTTPSuccess

        super
      end
    end.new("500", '{"error":{"message":"input (614 tokens) is too large to process. increase the physical batch size (current batch size: 512)"}}')
    allow(Net::HTTP).to receive(:start).and_return(response)

    expect do
      provider.send(:post_json, "http://reranker.example", "/v1/rerank", {})
    end.to raise_error(EmbeddingUtil::EndpointError, /--ubatch-size.*1024/)
  end

  it "falls back from missing /v1/rerank to /rerank" do
    calls = []
    allow(provider).to receive(:post_json) do |_endpoint, path, _payload|
      calls << path
      raise EmbeddingUtil::EndpointNotFoundError.new("http://reranker.example/v1/rerank", path: path) if path == "/v1/rerank"

      { "model" => "qwen3-reranker-0.6b", "results" => [{ "index" => 0, "score" => 1.0 }] }
    end

    result = provider.rerank("query", ["document"])

    expect(calls).to eq(["/v1/rerank", "/rerank"])
    expect(result.results.first.score).to eq(1.0)
  end
end
