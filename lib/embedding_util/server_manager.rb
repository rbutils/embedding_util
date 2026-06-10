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
    STOP_TIMEOUT = 30

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
        log_path = start_background(server_model) unless healthy_state?(state) || running_server_state?(state)
      end

      wait_for_healthy(server_model, log_path: log_path)
    end

    def serve(model:, runtime: config.runtime, shutdown_idle: config.shutdown_idle, host: config.host, port: nil)
      server_model = model.is_a?(ServerModel) ? model : ServerModel.parse(model)
      resolved_runtime = RuntimeCommand.resolve(runtime)
      selected_port = selected_port_for(server_model, host: host, port: port)
      command = runtime_command(resolved_runtime, server_model, host, selected_port)
      last_output_at = Time.now

      FileUtils.mkdir_p(config.state_dir)
      puts "starting #{server_model.name} with #{command.label} on http://#{host}:#{selected_port}"
      puts "shutdown idle: #{shutdown_idle}s" if shutdown_idle&.positive?

      previous_traps = install_interrupt_traps
      Open3.popen2e(*command.argv) do |_stdin, output, wait_thread|
        url = "http://#{host}:#{selected_port}"
        write_state(server_model, pid: state_pid(command, wait_thread), url: url, runtime: command.label, port: selected_port)
        last_output_at_mutex = Mutex.new
        reader = stream_output(output) { last_output_at_mutex.synchronize { last_output_at = Time.now } }
        wait_for_runtime_serving(command, server_model, url, wait_thread)
        supervise_runtime(command, wait_thread, shutdown_idle) { last_output_at_mutex.synchronize { last_output_at } }
      ensure
        cleanup_runtime(command, wait_thread)
        reader&.kill
        reader&.join
        delete_state(server_model)
        restore_interrupt_traps(previous_traps)
      end
    end

    def restart_server(capability, profile: config.resolved_profile)
      server_model = ServerModel.for(capability, profile)

      with_lock(server_model) do
        stopped_url = stop_server(server_model)
        wait_for_stopped(server_model, stopped_url)
        start_background(server_model)
      end

      wait_for_healthy(server_model, log_path: server_log_path(server_model))
    end

    def track_activity(capability, profile: config.resolved_profile)
      server_model = ServerModel.for(capability, profile)
      update_activity(server_model, 1)
      yield
    ensure
      update_activity(server_model, -1) if server_model
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
      argv.push("--reranker-ubatch-size", config.reranker_ubatch_size.to_s)
      argv.push("--reranker-max-ubatch-size", config.reranker_max_ubatch_size.to_s)
      argv.push("--ramalama-device", config.ramalama_device.to_s) unless config.ramalama_device.to_s.empty?
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

    def runtime_command(runtime, server_model, host, port)
      RuntimeCommand.new(
        runtime: runtime,
        server_model: server_model,
        host: host,
        port: port,
        server_flags: server_flags(server_model),
        ramalama_device: config.ramalama_device
      )
    end

    def server_flags(server_model)
      flags = server_model.settings.fetch(:server_flags)
      return flags unless server_model.capability == :reranker

      with_reranker_batch_size(flags, config.reranker_ubatch_size)
    end

    def with_reranker_batch_size(flags, size)
      filtered = []
      skip_next = false
      flags.each do |flag|
        if skip_next
          skip_next = false
          next
        end

        if ["--batch-size", "-b", "--ubatch-size", "-ub"].include?(flag)
          skip_next = true
          next
        end

        filtered << flag
      end
      filtered + ["--batch-size", size.to_s, "--ubatch-size", size.to_s]
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
      # Advisory only: the child runtime performs the real bind after this process releases the port.
      # with_lock serializes callers within a single process, but a cross-process race window
      # still exists between the probe socket closing here and the child process binding.
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
        raise UnsupportedProviderError, process_exited_message(server_model, log_path) if tracked_process_exited?(state)
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

          terminate_idle_process(pid)
        rescue Errno::ESRCH
          break
        end
      end
    end

    def stream_output(output)
      Thread.new do
        output.each_line do |line|
          yield
          print line
        end
      end
    end

    def wait_for_runtime_serving(command, server_model, url, wait_thread)
      warn "waiting for #{server_model.name} at #{url}" if config.verbose
      wait_for_serving(server_model, url, wait_thread.pid, wait_thread: wait_thread, check_process: !command.detached_server?)
      warn "#{server_model.name} is healthy" if config.verbose
    end

    def state_pid(command, wait_thread)
      command.detached_server? ? Process.pid : wait_thread.pid
    end

    def supervise_runtime(command, wait_thread, shutdown_idle, &last_output_at)
      warn "supervising #{command.server_name}" if config.verbose && command.detached_server?
      return supervise_detached_server(command, shutdown_idle, &last_output_at) if command.detached_server?

      watchdog = start_watchdog(wait_thread.pid, shutdown_idle, &last_output_at)
      wait_thread.value.exitstatus
    ensure
      watchdog&.kill
    end

    def wait_for_serving(server_model, url, pid, wait_thread: nil, check_process: true)
      deadline = Time.now + config.startup_timeout
      loop do
        return if healthy_url?(url)
        raise UnsupportedProviderError, "#{server_model.name} runtime launcher exited before server became healthy" if launcher_failed?(wait_thread)
        raise UnsupportedProviderError, "#{server_model.name} server process exited before becoming healthy" if check_process && !process_running?(pid)
        raise UnsupportedProviderError, "timed out after #{config.startup_timeout}s waiting for #{server_model.name} to become healthy" if Time.now >= deadline

        sleep 0.25
      end
    end

    def launcher_failed?(wait_thread)
      return false unless wait_thread && !wait_thread.alive?

      !wait_thread.value.success?
    end

    def supervise_detached_server(command, shutdown_idle)
      loop do
        if idle_expired?(shutdown_idle, command.server_model, yield)
          warn "stopping #{command.server_name} after #{shutdown_idle}s idle" if config.verbose
          stop_detached_server(command)
          return 0
        end

        sleep [shutdown_idle.to_f / 5.0, 1].max
      end
    rescue Interrupt
      stop_detached_server(command)
      130
    end

    def idle_expired?(shutdown_idle, server_model, last_output_at)
      return false unless shutdown_idle&.positive?

      activity = activity_state(server_model, last_output_at)
      activity.fetch(:active_requests).zero? && Time.now - activity.fetch(:last_activity_at) >= shutdown_idle
    end

    def activity_state(server_model, fallback_time)
      state = read_state(server_model)
      last_activity_at = parse_state_time(state&.fetch("last_activity_at", nil)) || fallback_time
      last_output_at = [fallback_time, last_activity_at].max
      {
        active_requests: Integer(state&.fetch("active_requests", 0) || 0),
        last_activity_at: last_output_at
      }
    rescue ArgumentError
      { active_requests: 0, last_activity_at: fallback_time }
    end

    def parse_state_time(value)
      Time.iso8601(value) if value
    rescue ArgumentError
      nil
    end

    def stop_detached_server(command)
      command.stop_argvs.any? do |stop_argv|
        system(*stop_argv, out: File::NULL, err: File::NULL)
      end
    end

    def stop_server(server_model)
      state = read_state(server_model)
      return delete_state(server_model) unless state

      runtime = state.fetch("runtime", config.runtime)
      port = state.fetch("port", server_model.default_port(config))
      url = state["url"]
      command = runtime_command(runtime, server_model, config.host, port)
      if command.detached_server?
        stop_detached_server(command)
      else
        terminate_runtime_process(command, state["pid"])
        stop_detached_server(runtime_command(:ramalama, server_model, config.host, port))
      end
      delete_state(server_model)
      url
    end

    def wait_for_stopped(server_model, url)
      return unless url

      deadline = Time.now + STOP_TIMEOUT
      loop do
        return unless healthy_url?(url)
        raise UnsupportedProviderError, "#{server_model.name} did not stop before restart" if Time.now >= deadline

        sleep 0.25
      end
    end

    def cleanup_runtime(command, wait_thread)
      return unless command

      if command.detached_server?
        stop_detached_server(command)
      else
        terminate_runtime_process(command, wait_thread&.pid)
      end
    end

    def terminate_runtime_process(command, pid)
      return if command.detached_server? || !pid || pid == Process.pid || !process_running?(pid)

      terminate_idle_process(pid)
    rescue Errno::ESRCH
      nil
    end

    def install_interrupt_traps
      %w[INT TERM].to_h do |signal|
        previous = Signal.trap(signal) { Thread.main.raise Interrupt }
        [signal, previous]
      end
    end

    def restore_interrupt_traps(previous_traps)
      previous_traps&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def terminate_idle_process(pid)
      Process.kill("TERM", pid)
      sleep 5
      Process.kill("KILL", pid) if process_running?(pid)
    end

    def startup_timeout_message(server_model, log_path)
      message = "timed out after #{config.startup_timeout}s waiting for #{server_model.name} to become healthy"
      return message unless log_path

      lines = log_tail(log_path)
      message += "\nlog: #{log_path}"
      message += "\nlast log lines:\n#{lines}" unless lines.empty?
      message
    end

    def process_exited_message(server_model, log_path)
      message = "#{server_model.name} server process exited before becoming healthy"
      return message unless log_path

      lines = log_tail(log_path)
      message += "\nlog: #{log_path}"
      message += "\nlast log lines:\n#{lines}" unless lines.empty?
      message
    end

    def log_tail(log_path)
      return "" unless File.exist?(log_path)

      File.readlines(log_path).last(20).join
    rescue Errno::ENOENT, Errno::EACCES, IOError
      ""
    end

    def healthy_state?(state)
      return false unless state && state["url"] && state["pid"]
      return false unless process_running?(state.fetch("pid"))

      healthy_url?(state.fetch("url"))
    end

    def running_server_state?(state)
      state && state["url"] && state["pid"] && process_running?(state.fetch("pid"))
    end

    def tracked_process_exited?(state)
      state && state["url"] && state["pid"] && !process_running?(state.fetch("pid"))
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
    rescue Errno::EPERM
      # Process exists but belongs to a different user; treat as running.
      true
    end

    def with_lock(server_model)
      FileUtils.mkdir_p(config.state_dir)
      File.open(lock_path(server_model), File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def write_state(server_model, pid:, url:, runtime:, port:)
      state = {
        pid: pid,
        url: url,
        profile: server_model.profile.name,
        capability: server_model.capability,
        runtime: runtime,
        port: port,
        active_requests: 0,
        last_activity_at: Time.now.utc.iso8601,
        updated_at: Time.now.utc.iso8601
      }
      File.write(state_path(server_model), JSON.pretty_generate(state))
    end

    def update_activity(server_model, delta)
      with_lock(server_model) do
        state = read_state(server_model)
        next unless state

        state["active_requests"] = [Integer(state.fetch("active_requests", 0)) + delta, 0].max
        state["last_activity_at"] = Time.now.utc.iso8601
        state["updated_at"] = Time.now.utc.iso8601
        File.write(state_path(server_model), JSON.pretty_generate(state))
      end
    rescue ArgumentError
      nil
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
