# frozen_string_literal: true

RSpec.describe EmbeddingUtil::Providers::SelfHosted do
  let(:provider) { described_class.new(config: EmbeddingUtil.configuration) }

  it "uses a self-hosted embedding endpoint after ensuring the server" do
    manager = instance_double(EmbeddingUtil::ServerManager, ensure_server: "http://127.0.0.1:18080")
    allow(manager).to receive(:track_activity).and_yield
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-embedding-0.6b",
      "data" => [{ "index" => 0, "embedding" => [0.1, 0.2] }]
    )

    result = provider.embed(["hello"])

    expect(result.embedding).to eq([[0.1, 0.2]])
    expect(manager).to have_received(:ensure_server).with(:embedding, profile: EmbeddingUtil.profile)
    expect(manager).to have_received(:track_activity).with(:embedding, profile: EmbeddingUtil.profile)
  end

  it "uses a self-hosted reranker endpoint after ensuring the server" do
    manager = instance_double(EmbeddingUtil::ServerManager, ensure_server: "http://127.0.0.1:18081")
    allow(manager).to receive(:track_activity).and_yield
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_return(
      "model" => "qwen3-reranker-0.6b",
      "results" => [{ "index" => 0, "relevance_score" => 0.8 }]
    )

    result = provider.rerank("query", ["document"])

    expect(result.results.first.score).to eq(0.8)
    expect(manager).to have_received(:ensure_server).with(:reranker, profile: EmbeddingUtil.profile)
    expect(manager).to have_received(:track_activity).with(:reranker, profile: EmbeddingUtil.profile)
  end

  it "restarts managed reranker with the max ubatch size after llama.cpp batch-size failures" do
    manager = instance_double(
      EmbeddingUtil::ServerManager,
      ensure_server: "http://127.0.0.1:18081",
      restart_server: "http://127.0.0.1:18081"
    )
    allow(manager).to receive(:track_activity).and_yield
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    calls = 0
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json) do
      calls += 1
      raise EmbeddingUtil::EndpointError, "increase the physical batch size" if calls == 1

      { "model" => "qwen3-reranker-0.6b", "results" => [{ "index" => 0, "relevance_score" => 0.9 }] }
    end

    result = provider.rerank("query", ["document"])

    expect(result.results.first.score).to eq(0.9)
    expect(EmbeddingUtil.configuration.reranker_ubatch_size).to eq(4096)
    expect(manager).to have_received(:restart_server).with(:reranker, profile: EmbeddingUtil.profile)
  end

  it "restarts managed reranker after a dropped rerank connection" do
    manager = instance_double(
      EmbeddingUtil::ServerManager,
      ensure_server: "http://127.0.0.1:18081",
      restart_server: "http://127.0.0.1:18081"
    )
    allow(manager).to receive(:track_activity).and_yield
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    calls = 0
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json) do
      calls += 1
      if calls == 1
        raise EmbeddingUtil::EndpointError,
              "could not reach http://127.0.0.1:18081/v1/rerank: end of file reached"
      end

      { "model" => "qwen3-reranker-0.6b", "results" => [{ "index" => 0, "relevance_score" => 0.9 }] }
    end

    result = provider.rerank("query", ["document"])

    expect(result.results.first.score).to eq(0.9)
    expect(EmbeddingUtil.configuration.reranker_ubatch_size).to eq(4096)
    expect(manager).to have_received(:restart_server).with(:reranker, profile: EmbeddingUtil.profile)
  end

  it "does not retry when the reranker is already at the max ubatch size" do
    EmbeddingUtil.configuration.reranker_ubatch_size = 4096
    manager = instance_double(EmbeddingUtil::ServerManager, ensure_server: "http://127.0.0.1:18081")
    allow(manager).to receive(:track_activity).and_yield
    allow(EmbeddingUtil::ServerManager).to receive(:new).and_return(manager)
    allow_any_instance_of(EmbeddingUtil::Providers::Endpoint).to receive(:post_json).and_raise(
      EmbeddingUtil::EndpointError,
      "increase the physical batch size"
    )

    expect do
      provider.rerank("query", ["document"])
    end.to raise_error(EmbeddingUtil::EndpointError, /physical batch size/)
  end
end
