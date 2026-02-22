defmodule Open890.RNNoisePort do
  use GenServer
  require Logger

  @name __MODULE__
  @default_timeout_ms 30

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec denoise(binary()) :: binary()
  def denoise(payload) when is_binary(payload) do
    call_timeout_ms = configured_timeout_ms() + 20

    try do
      GenServer.call(@name, {:denoise, payload}, call_timeout_ms)
    catch
      :exit, {:timeout, _} ->
        payload

      :exit, _ ->
        payload
    end
  end

  @spec enabled?() :: boolean()
  def enabled? do
    try do
      GenServer.call(@name, :enabled?)
    catch
      :exit, _ ->
        false
    end
  end

  @spec set_enabled(boolean()) :: boolean()
  def set_enabled(enabled) when is_boolean(enabled) do
    try do
      GenServer.call(@name, {:set_enabled, enabled})
    catch
      :exit, _ ->
        false
    end
  end

  @impl true
  def init(opts) do
    enabled = opts |> Keyword.get(:enabled, false)
    timeout_ms = opts |> Keyword.get(:timeout_ms, @default_timeout_ms)
    executable = opts |> Keyword.get(:executable, default_executable())

    state = %{
      enabled: enabled,
      timeout_ms: timeout_ms,
      executable: executable,
      port: nil,
      next_seq: 1
    }

    if enabled do
      {:ok, maybe_start_port(state)}
    else
      Logger.info("RNNoise disabled")
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, rnnoise_active?(state), state}
  end

  def handle_call({:set_enabled, false}, _from, state) do
    Logger.info("RNNoise disabled")

    next_state =
      state
      |> maybe_stop_port()
      |> Map.put(:enabled, false)

    {:reply, false, next_state}
  end

  def handle_call({:set_enabled, true}, _from, state) do
    next_state =
      state
      |> maybe_stop_port()
      |> Map.put(:enabled, true)
      |> maybe_start_port()

    {:reply, rnnoise_active?(next_state), next_state}
  end

  @impl true
  def handle_call({:denoise, payload}, _from, %{enabled: false} = state) do
    {:reply, payload, state}
  end

  def handle_call({:denoise, payload}, _from, %{port: nil} = state) do
    {:reply, payload, state}
  end

  def handle_call({:denoise, payload}, _from, state) do
    seq = state.next_seq
    req = <<seq::unsigned-big-32, payload::binary>>

    case Port.command(state.port, req) do
      true ->
        {reply_payload, next_state} = wait_for_reply(seq, payload, state)
        {:reply, reply_payload, next_state}

      false ->
        Logger.warn("RNNoise port command failed; using passthrough")
        {:reply, payload, %{state | port: nil, enabled: false}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warn("RNNoise helper exited status=#{status}; using passthrough")
    {:noreply, %{state | port: nil, enabled: false}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp wait_for_reply(seq, fallback, state) do
    timeout_ms = state.timeout_ms
    started_ms = System.monotonic_time(:millisecond)
    deadline_ms = started_ms + timeout_ms

    reply = await_reply(seq, state.port, deadline_ms)

    elapsed_ms = System.monotonic_time(:millisecond) - started_ms
    next_state = %{state | next_seq: bump_seq(seq)}

    case reply do
      {:ok, denoised} ->
        {denoised, next_state}

      {:error, :timeout} ->
        Logger.debug("RNNoise timeout after #{elapsed_ms}ms; using passthrough")
        {fallback, next_state}

      {:error, {:port_exited, status}} ->
        Logger.warn("RNNoise helper exited status=#{status}; using passthrough")
        {fallback, %{next_state | port: nil, enabled: false}}
    end
  end

  defp await_reply(seq, port, deadline_ms) do
    now_ms = System.monotonic_time(:millisecond)
    remaining_ms = max(deadline_ms - now_ms, 0)

    receive do
      {^port, {:data, <<^seq::unsigned-big-32, denoised::binary>>}} ->
        {:ok, denoised}

      {^port, {:data, <<other_seq::unsigned-big-32, _::binary>>}} ->
        Logger.debug("RNNoise out-of-order reply seq=#{other_seq}, expected=#{seq}")
        await_reply(seq, port, deadline_ms)

      {^port, {:exit_status, status}} ->
        {:error, {:port_exited, status}}
    after
      remaining_ms ->
        {:error, :timeout}
    end
  end

  defp maybe_start_port(%{port: port} = state) when port != nil, do: state

  defp maybe_start_port(%{executable: executable} = state) do
    if File.exists?(executable) do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:packet, 4}
        ])

      Logger.info("RNNoise helper enabled (#{executable})")
      %{state | port: port}
    else
      Logger.warn("RNNoise enabled but helper executable not found: #{executable}")
      %{state | enabled: false, port: nil}
    end
  end

  defp maybe_stop_port(%{port: nil} = state), do: state

  defp maybe_stop_port(%{port: port} = state) do
    try do
      Port.close(port)
    catch
      :exit, _ ->
        :ok
    end

    %{state | port: nil}
  end

  defp rnnoise_active?(state) do
    state.enabled and state.port != nil
  end

  defp bump_seq(0xFFFF_FFFF), do: 1
  defp bump_seq(seq), do: seq + 1

  defp configured_timeout_ms do
    Application.get_env(:open890, __MODULE__, [])
    |> Keyword.get(:timeout_ms, @default_timeout_ms)
  end

  defp default_executable do
    priv_dir =
      case :code.priv_dir(:open890) do
        dir when is_list(dir) -> to_string(dir)
        _ -> "priv"
      end

    candidates = [
      Path.join(priv_dir, "bin/open890_rnnoise_filter"),
      Path.join(priv_dir, "bin/open890_rnnoise_filter_static")
    ]

    Enum.find(candidates, &File.exists?/1) || hd(candidates)
  end
end
