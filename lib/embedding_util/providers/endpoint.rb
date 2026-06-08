# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "../provider"
require_relative "../result"

module EmbeddingUtil
  module Providers
    class Endpoint < Provider
      def supported?
        !!(config.embedding_endpoint_url || config.reranker_endpoint_url)
      end

      def support
        {
          provider: provider_name,
          supported: supported?,
          embedding_endpoint: config.embedding_endpoint_url,
          reranker_endpoint: config.reranker_endpoint_url
        }
      end

      def embed(texts, profile: config.resolved_profile)
        endpoint = require_endpoint(config.embedding_endpoint_url, "embedding")
        response = post_json(endpoint, "/v1/embeddings", {
                               input: texts,
                               model: profile.embedding.fetch(:model)
                             })

        data = Array(response.fetch("data"))
        embeddings = data.sort_by { |item| item.fetch("index", data.index(item) || 0) }.map { |item| item.fetch("embedding") }
        EmbeddingResult.new(
          embedding: texts.length == 1 ? embeddings.fetch(0) : embeddings,
          model: response["model"],
          profile: profile.name,
          provider: provider_name,
          metadata: { usage: response["usage"] }.compact
        )
      end

      def rerank(query, documents, profile: config.resolved_profile)
        endpoint = require_endpoint(config.reranker_endpoint_url, "reranker")
        response = begin
          post_json(endpoint, "/v1/rerank", rerank_payload(query, documents, profile))
        rescue EndpointNotFoundError
          post_json(endpoint, "/rerank", rerank_payload(query, documents, profile))
        end

        RerankResult.new(
          results: ranked_documents(response, documents),
          model: response["model"],
          profile: profile.name,
          provider: provider_name,
          metadata: { usage: response["usage"] }.compact
        )
      end

      private

      def rerank_payload(query, documents, profile)
        {
          query: query,
          documents: documents,
          model: profile.reranker.fetch(:model)
        }
      end

      def ranked_documents(response, documents)
        Array(response.fetch("results")).map do |item|
          index = item.fetch("index")
          RankedDocument.new(
            index: index,
            document: item["document"] || documents.fetch(index),
            score: item.fetch("relevance_score") { item.fetch("score") },
            metadata: item.reject { |key, _value| %w[index document relevance_score score].include?(key) }
          )
        end
      end

      def require_endpoint(endpoint, capability)
        raise UnsupportedProviderError, "no #{capability} endpoint configured" unless endpoint

        endpoint
      end

      def post_json(endpoint, path, payload)
        uri = URI.join(endpoint.end_with?("/") ? endpoint : "#{endpoint}/", path.sub(%r{\A/}, ""))
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", read_timeout: config.timeout, open_timeout: config.timeout) do |http|
          http.request(request)
        end

        raise EndpointNotFoundError, "#{uri} returned #{response.code}" if response.code.to_i == 404
        raise EndpointError, "#{uri} returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise EndpointError, "invalid JSON response from #{uri}: #{e.message}"
      rescue URI::InvalidURIError => e
        raise EndpointError, "invalid endpoint URL #{endpoint.inspect}: #{e.message}"
      end
    end
  end
end
