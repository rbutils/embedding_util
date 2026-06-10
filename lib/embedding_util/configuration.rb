# frozen_string_literal: true

module EmbeddingUtil
  class Configuration
    attr_accessor :profile, :provider, :endpoint, :embedding_endpoint, :reranker_endpoint, :timeout, :startup_timeout, :shutdown_idle, :host,
                  :embedding_port, :reranker_port, :state_dir, :verbose, :reranker_ubatch_size, :reranker_max_ubatch_size, :ramalama_device
    attr_reader :runtime

    def initialize
      @profile = :small_multilingual_v1
      @provider = :auto
      self.runtime = ENV.fetch("EMBEDDING_UTIL_RUNTIME", "auto")
      @endpoint = ENV["EMBEDDING_UTIL_ENDPOINT"]
      @embedding_endpoint = ENV["EMBEDDING_UTIL_EMBEDDING_ENDPOINT"]
      @reranker_endpoint = ENV["EMBEDDING_UTIL_RERANKER_ENDPOINT"]
      @timeout = Float(ENV.fetch("EMBEDDING_UTIL_TIMEOUT", "60"))
      @startup_timeout = Float(ENV.fetch("EMBEDDING_UTIL_STARTUP_TIMEOUT", "3600"))
      @shutdown_idle = Integer(ENV.fetch("EMBEDDING_UTIL_SHUTDOWN_IDLE", "300"))
      @host = ENV.fetch("EMBEDDING_UTIL_HOST", "127.0.0.1")
      @embedding_port = Integer(ENV.fetch("EMBEDDING_UTIL_EMBEDDING_PORT", "18080"))
      @reranker_port = Integer(ENV.fetch("EMBEDDING_UTIL_RERANKER_PORT", "18081"))
      @reranker_ubatch_size = Integer(ENV.fetch("EMBEDDING_UTIL_RERANKER_UBATCH_SIZE", "1024"))
      @reranker_max_ubatch_size = Integer(ENV.fetch("EMBEDDING_UTIL_RERANKER_MAX_UBATCH_SIZE", "4096"))
      @ramalama_device = ENV["EMBEDDING_UTIL_RAMALAMA_DEVICE"]
      @state_dir = ENV.fetch("EMBEDDING_UTIL_STATE_DIR", File.expand_path("~/.local/state/embedding_util"))
      @verbose = ENV.fetch("EMBEDDING_UTIL_VERBOSE", "false").match?(/\A(?:1|true|yes|on)\z/i)
    end

    def runtime=(value)
      @runtime = value.to_s.tr("-", "_").to_sym
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
