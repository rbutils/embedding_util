# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "../provider"
require_relative "../result"

module EmbeddingUtil
  module Providers
    class Endpoint < Provider
      NETWORK_ERRORS = [
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH,
        EOFError,
        IOError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        SocketError,
        Timeout::Error
      ].freeze

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
          embedding: embeddings,
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
        rescue EndpointNotFoundError => e
          raise unless fallback_rerank_not_found?(e)

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
            document: item["document"] || fetch_document_at(documents, index),
            score: item.fetch("relevance_score") { item.fetch("score") },
            metadata: item.reject { |key, _value| %w[index document relevance_score score].include?(key) }
          )
        end
      end

      def fetch_document_at(documents, index)
        documents.fetch(index)
      rescue IndexError
        raise EndpointError, "server returned out-of-range document index #{index.inspect} (#{documents.size} documents sent)"
      end

      def require_endpoint(endpoint, capability)
        raise UnsupportedProviderError, "no #{capability} endpoint configured" unless endpoint

        endpoint
      end

      def post_json(endpoint, path, payload)
        uri = endpoint_uri(endpoint, path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", read_timeout: config.timeout, open_timeout: config.timeout) do |http|
          http.request(request)
        end

        raise EndpointNotFoundError.new(uri, path: path, body: response.body) if response.code.to_i == 404 && route_missing_response?(response.body)
        raise EndpointError, "#{uri} returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise EndpointError, "invalid JSON response from #{uri}: #{e.message}"
      rescue URI::InvalidURIError => e
        raise EndpointError, "invalid endpoint URL #{endpoint.inspect}: #{e.message}"
      rescue *NETWORK_ERRORS => e
        raise EndpointError, "could not reach #{uri}: #{e.message}"
      end

      def endpoint_uri(endpoint, path)
        uri = URI(endpoint)
        segments = [uri.path, path].map { |part| part.to_s.gsub(%r{\A/+|/+\z}, "") }.reject(&:empty?)
        uri.path = "/#{segments.join('/')}"
        uri
      end

      def route_missing_response?(body)
        return true if body.to_s.strip.empty?

        JSON.parse(body)
        false
      rescue JSON::ParserError
        true
      end

      def fallback_rerank_not_found?(error)
        error.path == "/v1/rerank"
      end
    end
  end
end
