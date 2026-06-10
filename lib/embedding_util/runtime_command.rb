# frozen_string_literal: true

module EmbeddingUtil
  class RuntimeCommand
    attr_reader :runtime, :server_model, :host, :port, :server_flags

    def initialize(runtime:, server_model:, host:, port:, server_flags: nil)
      @runtime = self.class.normalize_runtime(runtime)
      @server_model = server_model
      @host = host
      @port = port
      @server_flags = server_flags || server_model.settings.fetch(:server_flags)
    end

    def self.available?(runtime)
      case normalize_runtime(runtime)
      when :auto
        available?(:ramalama) || available?(:llama_server)
      when :ramalama
        !!command_path("ramalama")
      when :llama_server
        !!command_path("llama-server")
      else
        false
      end
    end

    def self.resolve(runtime)
      requested = normalize_runtime(runtime)
      return requested unless requested == :auto

      return :ramalama if available?(:ramalama)
      return :llama_server if available?(:llama_server)

      :auto
    end

    def self.command_path(command)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, command) }.find { |path| File.executable?(path) && !File.directory?(path) }
    end

    def self.normalize_runtime(runtime)
      runtime.to_s.tr("-", "_").to_sym
    end

    def argv
      case runtime
      when :ramalama then ramalama_argv
      when :llama_server then llama_server_argv
      else raise UnsupportedProviderError, "no supported local runtime found; install ramalama or llama-server"
      end
    end

    def label
      runtime == :llama_server ? "llama-server" : runtime.to_s
    end

    def detached_server?
      runtime == :ramalama
    end

    def stop_argv
      return unless detached_server?

      stop_argvs.first
    end

    def stop_argvs
      return [] unless detached_server?

      [
        ["ramalama", "stop", server_name],
        ["podman", "stop", "--time", "0", server_name],
        ["docker", "stop", server_name]
      ].select { |argv| self.class.command_path(argv.first) }
    end

    def server_name
      "embedding-util-#{server_model.name}".tr("_", "-")
    end

    private

    def ramalama_argv
      [
        "ramalama", "--runtime=llama.cpp", "serve",
        "--name", server_name,
        "--host", host,
        "--port", port.to_s,
        "--runtime-args=#{server_flags.join(' ')}",
        huggingface_model
      ]
    end

    def llama_server_argv
      [
        "llama-server",
        "--host", host,
        "--port", port.to_s,
        "-hf", server_model.settings.fetch(:repo),
        "-hff", server_model.settings.fetch(:file),
        *server_flags
      ]
    end

    def huggingface_model
      "hf://#{server_model.settings.fetch(:repo)}/#{server_model.settings.fetch(:file)}"
    end
  end
end
