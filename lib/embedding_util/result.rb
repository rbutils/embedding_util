# frozen_string_literal: true

module EmbeddingUtil
  EmbeddingResult = Data.define(:embedding, :model, :profile, :provider, :metadata)
  RankedDocument = Data.define(:index, :document, :score, :metadata)
  RerankResult = Data.define(:results, :model, :profile, :provider, :metadata)
end
