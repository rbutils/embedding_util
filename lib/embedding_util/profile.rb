# frozen_string_literal: true

module EmbeddingUtil
  Profile = Data.define(:name, :embedding, :reranker) do
    def initialize(name:, embedding:, reranker:)
      super(name: name.to_sym, embedding: deep_freeze(embedding), reranker: deep_freeze(reranker))
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.transform_values { |item| deep_freeze(item) }.freeze
      when Array
        value.map { |item| deep_freeze(item) }.freeze
      else
        value.freeze
      end
    end
  end
end
