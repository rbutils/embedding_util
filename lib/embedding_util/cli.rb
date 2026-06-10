# frozen_string_literal: true

require "json"
require "thor"

module EmbeddingUtil
  class CLI < Thor
    CONFIG_OPTIONS = {
      profile: :to_sym.to_proc,
      runtime: ->(value) { RuntimeCommand.normalize_runtime(value) },
      endpoint: ->(value) { value },
      embedding_endpoint: ->(value) { value },
      reranker_endpoint: ->(value) { value },
      timeout: ->(value) { value },
      startup_timeout: ->(value) { value },
      shutdown_idle: :to_i.to_proc,
      reranker_ubatch_size: :to_i.to_proc,
      reranker_max_ubatch_size: :to_i.to_proc,
      verbose: ->(value) { value }
    }.freeze

    class_option :endpoint, type: :string, desc: "Endpoint serving both embedding and reranking APIs"
    class_option :embedding_endpoint, type: :string, desc: "Endpoint serving /v1/embeddings"
    class_option :reranker_endpoint, type: :string, desc: "Endpoint serving /v1/rerank or /rerank"
    class_option :profile, type: :string, desc: "Model profile"
    class_option :runtime, type: :string, desc: "Self-hosting runtime: auto, ramalama, or llama-server"
    class_option :timeout, type: :numeric, desc: "HTTP timeout in seconds"
    class_option :startup_timeout, type: :numeric, desc: "Seconds to wait for self-hosted server startup"
    class_option :shutdown_idle, type: :numeric, desc: "Stop self-hosted server after this many seconds without stdout/stderr activity"
    class_option :reranker_ubatch_size, type: :numeric, desc: "llama.cpp physical batch size for self-hosted reranker servers"
    class_option :reranker_max_ubatch_size, type: :numeric, desc: "Largest reranker physical batch size for automatic retry"
    class_option :verbose, type: :boolean, desc: "Print self-hosting diagnostics"

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
    rescue Error => e
      abort e.message
    end

    desc "rerank QUERY DOCUMENT...", "Rerank documents and print ranked results as JSON"
    def rerank(query, *documents)
      configure_embedding_util
      raise Error, "provide at least one document to rerank" if documents.empty?

      results = EmbeddingUtil.rerank(query, documents).map do |result|
        {
          index: result.index,
          document: result.document,
          score: result.score,
          metadata: result.metadata
        }
      end
      puts JSON.pretty_generate(results)
    rescue Error => e
      abort e.message
    end

    desc "serve", "Start one local model server and stop it after stdout/stderr is idle"
    option :model, type: :string, default: "embedding-small_multilingual_v1",
                   desc: "Model server to run, such as embedding-small_multilingual_v1 or reranker-small_multilingual_v1"
    option :port, type: :numeric, desc: "Port for the model server"
    option :host, type: :string, default: "127.0.0.1", desc: "Host for the model server"
    def serve
      configure_embedding_util
      ServerManager.new(config: EmbeddingUtil.configuration).serve(
        model: options[:model],
        runtime: options[:runtime] || EmbeddingUtil.configuration.runtime,
        shutdown_idle: options[:shutdown_idle]&.to_i,
        host: options[:host],
        port: options[:port]&.to_i
      )
    rescue Error => e
      abort e.message
    rescue Interrupt
      exit 130
    end

    no_commands do
      def configure_embedding_util
        EmbeddingUtil.configure do |config|
          cli_config.each do |key, value|
            config.public_send("#{key}=", value)
          end
        end
      end

      def cli_config
        CONFIG_OPTIONS.each_with_object({}) do |(key, coercion), values|
          value = options[key]
          next if value.nil?

          values[key] = coercion.call(value)
        end
      end
    end
  end
end
