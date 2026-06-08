# frozen_string_literal: true

require_relative "profile"

module EmbeddingUtil
  module Profiles
    SMALL_MULTILINGUAL_V1 = Profile.new(
      name: :small_multilingual_v1,
      embedding: {
        repo: "Qwen/Qwen3-Embedding-0.6B-GGUF",
        file: "Qwen3-Embedding-0.6B-Q8_0.gguf",
        model: "qwen3-embedding-0.6b",
        dimensions: 1024,
        normalize: true,
        pooling: "last",
        server_flags: ["--embedding", "--pooling", "last"]
      },
      reranker: {
        repo: "ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF",
        file: "qwen3-reranker-0.6b-q8_0.gguf",
        model: "qwen3-reranker-0.6b",
        server_flags: ["--reranking"]
      }
    )

    BY_NAME = {
      SMALL_MULTILINGUAL_V1.name => SMALL_MULTILINGUAL_V1
    }.freeze

    module_function

    def fetch(name)
      BY_NAME.fetch(name.to_sym) do
        raise ArgumentError, "unknown embedding_util profile: #{name.inspect}"
      end
    end

    def all
      BY_NAME.values
    end
  end
end
