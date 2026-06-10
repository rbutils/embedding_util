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
        manager = ServerManager.new(config: config)
        endpoint = manager.ensure_server(:embedding, profile: profile)
        manager.track_activity(:embedding, profile: profile) do
          endpoint_provider(embedding_endpoint: endpoint).embed(texts, profile: profile)
        end
      end

      def rerank(query, documents, profile: config.resolved_profile)
        manager = ServerManager.new(config: config)
        endpoint = manager.ensure_server(:reranker, profile: profile)
        rerank_with_activity(manager, endpoint, query, documents, profile)
      rescue EndpointError => e
        raise unless retryable_reranker_error?(e) && can_escalate_reranker_ubatch?

        config.reranker_ubatch_size = config.reranker_max_ubatch_size
        endpoint = manager.restart_server(:reranker, profile: profile)
        rerank_with_activity(manager, endpoint, query, documents, profile)
      end

      private

      def endpoint_provider(embedding_endpoint: nil, reranker_endpoint: nil)
        endpoint_config = config.dup
        endpoint_config.embedding_endpoint = embedding_endpoint
        endpoint_config.reranker_endpoint = reranker_endpoint
        Endpoint.new(config: endpoint_config)
      end

      def rerank_with_activity(manager, endpoint, query, documents, profile)
        manager.track_activity(:reranker, profile: profile) do
          endpoint_provider(reranker_endpoint: endpoint).rerank(query, documents, profile: profile)
        end
      end

      def reranker_batch_size_error?(error)
        error.message.include?("increase the physical batch size")
      end

      def retryable_reranker_error?(error)
        reranker_batch_size_error?(error) || reranker_connection_dropped?(error)
      end

      def reranker_connection_dropped?(error)
        error.message.match?(%r{could not reach http://[^ ]+/v1/rerank: (?:end of file reached|Connection reset|connection reset|stream closed)})
      end

      def can_escalate_reranker_ubatch?
        config.reranker_ubatch_size < config.reranker_max_ubatch_size
      end
    end
  end
end
