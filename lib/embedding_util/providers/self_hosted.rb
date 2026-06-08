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
        endpoint = ServerManager.new(config: config).ensure_server(:reranker, profile: profile)
        endpoint_provider(reranker_endpoint: endpoint).rerank(query, documents, profile: profile)
      end

      private

      def endpoint_provider(embedding_endpoint: nil, reranker_endpoint: nil)
        endpoint_config = config.dup
        endpoint_config.embedding_endpoint = embedding_endpoint
        endpoint_config.reranker_endpoint = reranker_endpoint
        Endpoint.new(config: endpoint_config)
      end
    end
  end
end
