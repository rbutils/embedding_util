# frozen_string_literal: true

RSpec.describe EmbeddingUtil::ServerModel do
  it "parses embedding model names" do
    model = described_class.parse("embedding-small_multilingual_v1")

    expect(model.capability).to eq(:embedding)
    expect(model.profile.name).to eq(:small_multilingual_v1)
    expect(model.name).to eq("embedding-small_multilingual_v1")
    expect(model.settings.fetch(:server_flags)).to eq(["--embedding", "--pooling", "last"])
  end

  it "parses reranker model names" do
    model = described_class.parse("reranker-small_multilingual_v1")

    expect(model.capability).to eq(:reranker)
    expect(model.profile.name).to eq(:small_multilingual_v1)
    expect(model.name).to eq("reranker-small_multilingual_v1")
    expect(model.settings.fetch(:server_flags)).to eq(["--reranking", "--ubatch-size", "1024"])
  end
end
