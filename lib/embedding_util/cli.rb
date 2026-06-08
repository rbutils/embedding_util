# frozen_string_literal: true

require "json"
require "thor"

module EmbeddingUtil
  class CLI < Thor
    class_option :endpoint, type: :string, desc: "Endpoint serving both embedding and reranking APIs"
    class_option :embedding_endpoint, type: :string, desc: "Endpoint serving /v1/embeddings"
    class_option :reranker_endpoint, type: :string, desc: "Endpoint serving /v1/rerank or /rerank"
    class_option :profile, type: :string, default: "small_multilingual_v1", desc: "Model profile"
    class_option :timeout, type: :numeric, desc: "HTTP timeout in seconds"

    desc "support", "Display configured provider support"
    def support
      configure_embedding_util
      EmbeddingUtil.support.each do |item|
        status = item.fetch(:supported) ? "supported" : "not supported"
        puts "#{item.fetch(:provider)}: #{status}"
        puts "  embedding_endpoint: #{item.fetch(:embedding_endpoint)}" if item[:embedding_endpoint]
        puts "  reranker_endpoint: #{item.fetch(:reranker_endpoint)}" if item[:reranker_endpoint]
      end
    end

    desc "profiles", "List known model profiles"
    def profiles
      EmbeddingUtil.profiles.each do |profile|
        puts profile.name
        puts "  embedding: #{profile.embedding.fetch(:repo)} / #{profile.embedding.fetch(:file)}"
        puts "  reranker:  #{profile.reranker.fetch(:repo)} / #{profile.reranker.fetch(:file)}"
      end
    end

    desc "embed TEXT", "Compute one embedding and print it as JSON"
    def embed(text)
      configure_embedding_util
      puts JSON.generate(EmbeddingUtil.embed(text))
    end

    desc "rerank QUERY DOCUMENT...", "Rerank documents and print ranked results as JSON"
    def rerank(query, *documents)
      raise Error, "provide at least one document to rerank" if documents.empty?

      configure_embedding_util
      results = EmbeddingUtil.rerank(query, documents).map do |result|
        {
          index: result.index,
          document: result.document,
          score: result.score,
          metadata: result.metadata
        }
      end
      puts JSON.pretty_generate(results)
    end

    no_commands do
      def configure_embedding_util
        EmbeddingUtil.configure do |config|
          config.profile = options[:profile].to_sym if options[:profile]
          config.endpoint = options[:endpoint] if options[:endpoint]
          config.embedding_endpoint = options[:embedding_endpoint] if options[:embedding_endpoint]
          config.reranker_endpoint = options[:reranker_endpoint] if options[:reranker_endpoint]
          config.timeout = options[:timeout] if options[:timeout]
        end
      end
    end
  end
end
