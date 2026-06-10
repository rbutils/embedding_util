# frozen_string_literal: true

require_relative "../provider"
require_relative "../server_manager"
require_relative "endpoint"

module EmbeddingUtil
  module Providers
    class SelfHosted < Provider
      def supported?
        ServerManager.supported?(config)
      end

      def support
        {
          provider: provider_name,
          supported: supported?,
          runtime: RuntimeCommand.resolve(config.runtime),
          shutdown_idle: config.shutdown_idle,
          state_dir: config.state_dir
        }
      end

      def embed(texts, profile: config.resolved_profile)
        endpoint = ServerManager.new(config: config).ensure_server(:embedding, profile: profile)
        endpoint_provider(embedding_endpoint: endpoint).embed(texts, profile: profile)
      end

      def rerank(query, documents, profile: config.resolved_profile)
        manager = ServerManager.new(config: config)
        endpoint = manager.ensure_server(:reranker, profile: profile)
        endpoint_provider(reranker_endpoint: endpoint).rerank(query, documents, profile: profile)
      rescue EndpointError => e
        raise unless reranker_batch_size_error?(e) && can_escalate_reranker_ubatch?

        config.reranker_ubatch_size = config.reranker_max_ubatch_size
        endpoint = manager.restart_server(:reranker, profile: profile)
        endpoint_provider(reranker_endpoint: endpoint).rerank(query, documents, profile: profile)
      end

      private

      def endpoint_provider(embedding_endpoint: nil, reranker_endpoint: nil)
        endpoint_config = config.dup
        endpoint_config.embedding_endpoint = embedding_endpoint
        endpoint_config.reranker_endpoint = reranker_endpoint
        Endpoint.new(config: endpoint_config)
      end

      def reranker_batch_size_error?(error)
        error.message.include?("increase the physical batch size")
      end

      def can_escalate_reranker_ubatch?
        config.reranker_ubatch_size < config.reranker_max_ubatch_size
      end
    end
  end
end
