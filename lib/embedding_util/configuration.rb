# frozen_string_literal: true

module EmbeddingUtil
  class Configuration
    attr_accessor :profile, :provider, :endpoint, :embedding_endpoint, :reranker_endpoint, :timeout

    def initialize
      @profile = :small_multilingual_v1
      @provider = :auto
      @endpoint = ENV["EMBEDDING_UTIL_ENDPOINT"]
      @embedding_endpoint = ENV["EMBEDDING_UTIL_EMBEDDING_ENDPOINT"]
      @reranker_endpoint = ENV["EMBEDDING_UTIL_RERANKER_ENDPOINT"]
      @timeout = Float(ENV.fetch("EMBEDDING_UTIL_TIMEOUT", "60"))
    end

    def resolved_profile
      profile.is_a?(Profile) ? profile : Profiles.fetch(profile)
    end

    def embedding_endpoint_url
      embedding_endpoint || endpoint
    end

    def reranker_endpoint_url
      reranker_endpoint || endpoint
    end
  end
end
