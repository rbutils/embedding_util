# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "rbconfig"
require "socket"
require "time"
require "uri"

module EmbeddingUtil
  class ServerManager
    attr_reader :config

    def initialize(config: EmbeddingUtil.configuration)
      @config = config
    end

    def self.supported?(config = EmbeddingUtil.configuration)
      RuntimeCommand.available?(config.runtime)
    end

    def ensure_server(capability, profile: config.resolved_profile)
      server_model = ServerModel.for(capability, profile)
      log_path = server_log_path(server_model)

      with_lock(server_model) do
        state = read_state(server_model)
        return state.fetch("url") if healthy_state?(state)

        log_path = start_background(server_model) unless starting_state?(state)
      end

      wait_for_healthy(server_model, log_path: log_path)
    end

    def serve(model:, runtime: config.runtime, shutdown_idle: config.shutdown_idle, host: config.host, port: nil)
      server_model = model.is_a?(ServerModel) ? model : ServerModel.parse(model)
      resolved_runtime = RuntimeCommand.resolve(runtime)
      selected_port = selected_port_for(server_model, host: host, port: port)
      command = RuntimeCommand.new(runtime: resolved_runtime, server_model: server_model, host: host, port: selected_port)
      last_output_at = Time.now

      FileUtils.mkdir_p(config.state_dir)
      puts "starting #{server_model.name} with #{command.label} on http://#{host}:#{selected_port}"
      puts "shutdown idle: #{shutdown_idle}s" if shutdown_idle&.positive?

      Open3.popen2e(*command.argv) do |_stdin, output, wait_thread|
        write_state(server_model, pid: wait_thread.pid, url: "http://#{host}:#{selected_port}", runtime: command.label, port: selected_port)
        watchdog = start_watchdog(wait_thread.pid, shutdown_idle) { last_output_at }

        output.each_line do |line|
          last_output_at = Time.now
          print line
        end

        watchdog&.kill
        delete_state(server_model)
        wait_thread.value.exitstatus
      end
    end

    private

    def start_background(server_model)
      FileUtils.mkdir_p(config.state_dir)
      log_path = server_log_path(server_model)
      selected_port = selected_port_for(server_model, host: config.host)
      argv = [
        RbConfig.ruby, executable_path, "serve",
        "--model", server_model.name,
        "--runtime", config.runtime.to_s,
        "--host", config.host,
        "--port", selected_port.to_s
      ]
      argv.push("--shutdown-idle", config.shutdown_idle.to_s) unless config.shutdown_idle.nil?
      warn "starting #{server_model.name} in background: #{argv.join(' ')}" if config.verbose
      warn "#{server_model.name} log: #{log_path}" if config.verbose
      pid = Process.spawn(*argv, out: [log_path, "a"], err: %i[child out], pgroup: true)
      write_state(server_model, pid: pid, url: "http://#{config.host}:#{selected_port}", runtime: "starting", port: selected_port)
      Process.detach(pid)
      log_path
    end

    def server_log_path(server_model)
      File.join(config.state_dir, "#{server_model.name}.log")
    end

    def executable_path
      local_path = File.expand_path("../../exe/embedding_util", __dir__)
      return local_path if File.exist?(local_path)

      Gem.bin_path("embedding_util", "embedding_util")
    end

    def selected_port_for(server_model, host:, port: nil)
      return required_port(host, port) if port

      available_port(host, server_model.default_port(config))
    end

    def required_port(host, port)
      return port if port_available?(host, port)

      raise UnsupportedProviderError, "port #{host}:#{port} is already in use"
    end

    def available_port(host, preferred_port)
      (preferred_port...(preferred_port + 100)).find { |candidate| port_available?(host, candidate) } || raise(
        UnsupportedProviderError,
        "no free port found for #{host} starting at #{preferred_port}"
      )
    end

    def port_available?(host, port)
      server = TCPServer.new(host, port)
      true
    rescue Errno::EADDRINUSE, Errno::EACCES, SocketError
      false
    ensure
      server&.close
    end

    def wait_for_healthy(server_model, log_path: nil)
      deadline = Time.now + config.startup_timeout
      loop do
        state = read_state(server_model)
        return state.fetch("url") if healthy_state?(state)
        raise UnsupportedProviderError, startup_timeout_message(server_model, log_path) if Time.now >= deadline

        sleep 0.25
      end
    end

    def start_watchdog(pid, shutdown_idle)
      return unless shutdown_idle&.positive?

      Thread.new do
        loop do
          sleep [shutdown_idle / 5.0, 1].max
          next if Time.now - yield < shutdown_idle

          Process.kill("TERM", pid)
          sleep 5
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          break
        end
      end
    end

    def startup_timeout_message(server_model, log_path)
      message = "timed out after #{config.startup_timeout}s waiting for #{server_model.name} to become healthy"
      return message unless log_path

      lines = log_tail(log_path)
      message += "\nlog: #{log_path}"
      message += "\nlast log lines:\n#{lines}" unless lines.empty?
      message
    end

    def log_tail(log_path)
      return "" unless File.exist?(log_path)

      File.readlines(log_path).last(20).join
    rescue StandardError
      ""
    end

    def healthy_state?(state)
      return false unless state && state["url"] && state["pid"]
      return false unless process_running?(state.fetch("pid"))

      healthy_url?(state.fetch("url"))
    end

    def starting_state?(state)
      state && state["url"] && state["pid"] && process_running?(state.fetch("pid"))
    end

    def healthy_url?(url)
      uri = URI.join(url.end_with?("/") ? url : "#{url}/", "health")
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", read_timeout: 2, open_timeout: 2) { |http| http.get(uri) }
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def process_running?(pid)
      Process.kill(0, Integer(pid))
      true
    rescue Errno::ESRCH, ArgumentError
      false
    end

    def with_lock(server_model)
      FileUtils.mkdir_p(config.state_dir)
      File.open(lock_path(server_model), File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def write_state(server_model, pid:, url:, runtime:, port:)
      File.write(state_path(server_model), JSON.pretty_generate({
                                                                  pid: pid,
                                                                  url: url,
                                                                  profile: server_model.profile.name,
                                                                  capability: server_model.capability,
                                                                  runtime: runtime,
                                                                  port: port,
                                                                  updated_at: Time.now.utc.iso8601
                                                                }))
    end

    def read_state(server_model)
      JSON.parse(File.read(state_path(server_model)))
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def delete_state(server_model)
      FileUtils.rm_f(state_path(server_model))
    end

    def state_path(server_model)
      File.join(config.state_dir, "#{server_model.name}.json")
    end

    def lock_path(server_model)
      File.join(config.state_dir, "#{server_model.name}.lock")
    end
  end
end
