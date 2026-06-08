# frozen_string_literal: true

module EmbeddingUtil
  SERVER_MODEL_PREFIXES = {
    "embedding" => :embedding,
    "reranker" => :reranker,
    "rerank" => :reranker
  }.freeze

  ServerModel = Data.define(:capability, :profile) do
    def self.parse(value)
      text = value.to_s
      prefix, profile_name = text.split("-", 2)
      capability = SERVER_MODEL_PREFIXES[prefix]
      raise ArgumentError, "unknown server model #{value.inspect}; expected embedding-PROFILE or reranker-PROFILE" unless capability && profile_name

      new(capability: capability, profile: Profiles.fetch(profile_name))
    end

    def self.for(capability, profile)
      new(capability: capability.to_sym, profile: profile)
    end

    def name
      "#{capability_name}-#{profile.name}"
    end

    def settings
      case capability
      when :embedding then profile.embedding
      when :reranker then profile.reranker
      else raise ArgumentError, "unknown server capability: #{capability.inspect}"
      end
    end

    def default_port(config)
      capability == :embedding ? config.embedding_port : config.reranker_port
    end

    private

    def capability_name
      capability == :reranker ? "reranker" : capability.to_s
    end
  end
end
