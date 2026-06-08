# frozen_string_literal: true

module EmbeddingUtil
  class Provider
    attr_reader :config

    def initialize(config: EmbeddingUtil.configuration)
      @config = config
    end

    def self.provider_name
      name.split("::").last.gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase.to_sym
    end

    def self.supported?(config = EmbeddingUtil.configuration)
      new(config: config).supported?
    end

    def provider_name
      self.class.provider_name
    end

    def supported?
      false
    end

    def support
      { provider: provider_name, supported: supported? }
    end
  end
end
