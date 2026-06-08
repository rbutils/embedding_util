# frozen_string_literal: true

module EmbeddingUtil
  class ProviderRegistry
    attr_reader :providers

    def initialize
      @providers = []
    end

    def register(provider_class)
      @providers << provider_class unless @providers.include?(provider_class)
    end

    def resolve(config: EmbeddingUtil.configuration)
      selected = config.provider
      return resolve_selected(selected, config) if selected && selected != :auto

      provider_class = providers.find { |candidate| candidate.supported?(config) }
      raise UnsupportedProviderError, unsupported_message unless provider_class

      provider_class.new(config: config)
    end

    def support(config: EmbeddingUtil.configuration)
      providers.map { |provider_class| provider_class.new(config: config).support }
    end

    private

    def resolve_selected(selected, config)
      provider_class = providers.find { |candidate| candidate.provider_name == selected.to_sym }
      raise UnsupportedProviderError, "unknown embedding_util provider: #{selected.inspect}" unless provider_class

      provider = provider_class.new(config: config)
      raise UnsupportedProviderError, unsupported_message(selected) unless provider.supported?

      provider
    end

    def unsupported_message(provider = nil)
      target = provider ? "provider #{provider.inspect}" : "a supported local embedding provider"
      <<~MESSAGE.strip
        Could not find #{target}.

        For this implementation slice, configure already-running local endpoints:
          EmbeddingUtil.configure { |c| c.embedding_endpoint = "http://127.0.0.1:18080" }
          EmbeddingUtil.configure { |c| c.reranker_endpoint = "http://127.0.0.1:18081" }

        A single endpoint can be used with c.endpoint if it serves both /v1/embeddings and /v1/rerank.
        Local process provisioning through Ramalama or llama.cpp is intentionally not enabled yet.
      MESSAGE
    end
  end
end
