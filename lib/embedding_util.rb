# frozen_string_literal: true

require_relative "embedding_util/version"

module EmbeddingUtil
  class Error < StandardError; end
  class UnsupportedProviderError < Error; end
  class EndpointError < Error; end
  class EndpointNotFoundError < EndpointError; end

  autoload :Configuration, "embedding_util/configuration"
  autoload :CLI, "embedding_util/cli"
  autoload :EmbeddingResult, "embedding_util/result"
  autoload :Profile, "embedding_util/profile"
  autoload :Profiles, "embedding_util/profiles"
  autoload :Provider, "embedding_util/provider"
  autoload :ProviderRegistry, "embedding_util/provider_registry"
  autoload :RankedDocument, "embedding_util/result"
  autoload :RerankResult, "embedding_util/result"
  autoload :ServerManager, "embedding_util/server_manager"
  autoload :ServerModel, "embedding_util/server_model"
  autoload :RuntimeCommand, "embedding_util/runtime_command"

  module Providers
    autoload :Endpoint, "embedding_util/providers/endpoint"
    autoload :SelfHosted, "embedding_util/providers/self_hosted"
  end

  module_function

  def configuration
    @configuration ||= Configuration.new
  end

  def configure
    yield configuration
  end

  def reset_configuration!
    @configuration = Configuration.new
    @registry = nil
  end

  def registry
    @registry ||= begin
      registry = ProviderRegistry.new
      registry.register(Providers::Endpoint)
      registry.register(Providers::SelfHosted)
      registry
    end
  end

  def register_provider(provider_class)
    registry.register(provider_class)
  end

  def support
    registry.support(config: configuration)
  end

  def embed(text, **options)
    embed_result(text, **options).embedding
  end

  def embed_many(texts, **options)
    embed_result(texts, **options).embedding
  end

  def embed_result(input, profile: configuration.resolved_profile, provider: nil)
    texts = normalize_texts(input)
    selected_provider(provider).embed(texts, profile: resolve_profile(profile))
  end

  def rerank(query, documents, **options)
    rerank_result(query, documents, **options).results
  end

  def rerank_result(query, documents, profile: configuration.resolved_profile, provider: nil)
    selected_provider(provider).rerank(query.to_s, Array(documents).map(&:to_s), profile: resolve_profile(profile))
  end

  def profiles
    Profiles.all
  end

  def profile(name = configuration.profile)
    resolve_profile(name)
  end

  def normalize_texts(input)
    input.is_a?(Array) ? input.map(&:to_s) : [input.to_s]
  end

  def resolve_profile(value)
    value.is_a?(Profile) ? value : Profiles.fetch(value)
  end

  def selected_provider(provider)
    return registry.resolve(config: configuration) unless provider

    previous = configuration.provider
    configuration.provider = provider
    registry.resolve(config: configuration)
  ensure
    configuration.provider = previous if provider
  end
end
