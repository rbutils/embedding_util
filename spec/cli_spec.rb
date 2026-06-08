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
end
