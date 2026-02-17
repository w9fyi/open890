defmodule Open890.FT8DecoderPort do
  use GenServer
  require Logger

  alias Open890Web.Endpoint

  @name __MODULE__
  @default_timeout_ms 1200
  @default_window_seconds 15
  @default_sample_rate_hz 16_000
  @max_recent_decodes 50

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec ingest(binary()) :: :ok
  def ingest(payload) when is_binary(payload) do
    GenServer.cast(@name, {:ingest, payload})
  catch
    :exit, _ ->
      :ok
  end

  @spec enabled?() :: boolean()
  def enabled? do
    GenServer.call(@name, :enabled?)
  catch
    :exit, _ ->
      false
  end

  @spec set_enabled(boolean()) :: boolean()
  def set_enabled(enabled) when is_boolean(enabled) do
    GenServer.call(@name, {:set_enabled, enabled})
  catch
    :exit, _ ->
      false
  end

  @spec status() :: map()
  def status do
    GenServer.call(@name, :status)
  catch
    :exit, _ ->
      %{enabled: false, active: false, recent_decodes: 0, last_error: "ft8 service unavailable"}
  end

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, false)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    executable = Keyword.get(opts, :executable, default_executable())
    sample_rate_hz = Keyword.get(opts, :sample_rate_hz, @default_sample_rate_hz)
    window_seconds = Keyword.get(opts, :window_seconds, @default_window_seconds)

    window_bytes = sample_rate_hz * window_seconds * 2

    state = %{
      enabled: enabled,
      timeout_ms: timeout_ms,
      executable: executable,
      sample_rate_hz: sample_rate_hz,
      window_seconds: window_seconds,
      window_bytes: window_bytes,
      port: nil,
      next_seq: 1,
      buffer: <<>>,
      recent: [],
      last_error: nil,
      last_decode_at: nil
    }

    next_state =
      if enabled do
        maybe_start_port(state)
      else
        Logger.info("FT8 decoder disabled")
        state
      end

    broadcast_status(next_state)

    {:ok, next_state}
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, ft8_active?(state), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, status_map(state), state}
  end

  def handle_call({:set_enabled, false}, _from, state) do
    Logger.info("FT8 decoder disabled")

    next_state =
      state
      |> maybe_stop_port()
      |> Map.put(:enabled, false)
      |> Map.put(:last_error, nil)

    broadcast_status(next_state)

    {:reply, false, next_state}
  end

  def handle_call({:set_enabled, true}, _from, state) do
    next_state =
      state
      |> maybe_stop_port()
      |> Map.put(:enabled, true)
      |> Map.put(:last_error, nil)
      |> maybe_start_port()

    broadcast_status(next_state)

    {:reply, ft8_active?(next_state), next_state}
  end

  @impl true
  def handle_cast({:ingest, payload}, %{enabled: false} = state) when is_binary(payload) do
    {:noreply, state}
  end

  def handle_cast({:ingest, payload}, %{port: nil} = state) when is_binary(payload) do
    {:noreply, state}
  end

  def handle_cast({:ingest, payload}, state) when is_binary(payload) do
    next_state =
      state
      |> append_audio(payload)
      |> maybe_decode_windows()

    {:noreply, next_state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warn("FT8 helper exited status=#{status}")

    next_state = %{
      state
      | port: nil,
        enabled: false,
        last_error: "helper exited status=#{status}"
    }

    broadcast_status(next_state)

    {:noreply, next_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp append_audio(state, payload) do
    %{state | buffer: state.buffer <> payload}
  end

  defp maybe_decode_windows(%{window_bytes: window_bytes, buffer: buffer} = state)
       when byte_size(buffer) < window_bytes do
    state
  end

  defp maybe_decode_windows(state) do
    <<window::binary-size(state.window_bytes), rest::binary>> = state.buffer

    next_state = %{state | buffer: rest}

    next_state =
      case decode_window(window, next_state) do
        {:ok, decodes, updated_state} ->
          publish_decodes(decodes)
          updated_state

        {:error, reason, updated_state} ->
          Logger.debug("FT8 decode window failed: #{inspect(reason)}")
          updated_state
      end

    maybe_decode_windows(next_state)
  end

  defp decode_window(_window, %{port: nil} = state) do
    {:error, :no_port, state}
  end

  defp decode_window(window, state) do
    seq = state.next_seq
    req = <<seq::unsigned-big-32, window::binary>>

    case Port.command(state.port, req) do
      true ->
        case wait_for_reply(seq, state.timeout_ms, state.port) do
          {:ok, payload} ->
            parse_result(payload, state)

          {:error, reason} ->
            next_state = %{state | next_seq: bump_seq(seq), last_error: inspect(reason)}
            broadcast_status(next_state)
            {:error, reason, next_state}
        end

      false ->
        next_state = %{state | port: nil, enabled: false, last_error: "port command failed"}
        broadcast_status(next_state)
        {:error, :port_command_failed, next_state}
    end
  end

  defp wait_for_reply(seq, timeout_ms, port) do
    receive do
      {^port, {:data, <<^seq::unsigned-big-32, payload::binary>>}} ->
        {:ok, payload}

      {^port, {:data, <<other_seq::unsigned-big-32, _::binary>>}} ->
        Logger.debug("FT8 out-of-order reply seq=#{other_seq}, expected=#{seq}")
        wait_for_reply(seq, timeout_ms, port)

      {^port, {:exit_status, status}} ->
        {:error, {:port_exited, status}}
    after
      timeout_ms ->
        {:error, :timeout}
    end
  end

  defp parse_result(payload, state) do
    next_state = %{state | next_seq: bump_seq(state.next_seq), last_decode_at: DateTime.utc_now()}

    with {:ok, decoded} <- Jason.decode(payload),
         decodes when is_list(decodes) <- Map.get(decoded, "decodes", []) do
      normalized = decodes |> Enum.map(&normalize_decode/1)

      recent =
        (normalized ++ next_state.recent)
        |> Enum.take(@max_recent_decodes)

      updated_state = %{next_state | recent: recent, last_error: nil}
      broadcast_status(updated_state)

      {:ok, normalized, updated_state}
    else
      reason ->
        updated_state = %{next_state | last_error: "decode parse error: #{inspect(reason)}"}
        broadcast_status(updated_state)
        {:error, reason, updated_state}
    end
  end

  defp normalize_decode(entry) when is_map(entry) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      timestamp: Map.get(entry, "timestamp", Map.get(entry, :timestamp, now)),
      snr: Map.get(entry, "snr", Map.get(entry, :snr, nil)),
      dt: Map.get(entry, "dt", Map.get(entry, :dt, nil)),
      freq_hz: Map.get(entry, "freq_hz", Map.get(entry, :freq_hz, nil)),
      text: Map.get(entry, "text", Map.get(entry, :text, ""))
    }
  end

  defp normalize_decode(other) do
    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      snr: nil,
      dt: nil,
      freq_hz: nil,
      text: inspect(other)
    }
  end

  defp publish_decodes(decodes) do
    Enum.each(decodes, fn decode ->
      Endpoint.broadcast("radio:ft8", "ft8_decode", decode)
    end)
  end

  defp status_map(state) do
    %{
      enabled: state.enabled,
      active: ft8_active?(state),
      executable: state.executable,
      sample_rate_hz: state.sample_rate_hz,
      window_seconds: state.window_seconds,
      recent_decodes: length(state.recent),
      last_error: state.last_error,
      last_decode_at: format_datetime(state.last_decode_at)
    }
  end

  defp broadcast_status(state) do
    Endpoint.broadcast("radio:ft8", "ft8_status", status_map(state))
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_start_port(%{port: port} = state) when port != nil, do: state

  defp maybe_start_port(%{executable: executable} = state) do
    if File.exists?(executable) do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:packet, 4}
        ])

      Logger.info("FT8 helper enabled (#{executable})")
      %{state | port: port, last_error: nil}
    else
      Logger.warn("FT8 enabled but helper executable not found: #{executable}")
      %{state | enabled: false, port: nil, last_error: "helper not found"}
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

  defp ft8_active?(state) do
    state.enabled and state.port != nil
  end

  defp bump_seq(0xFFFF_FFFF), do: 1
  defp bump_seq(seq), do: seq + 1

  defp default_executable do
    :code.priv_dir(:open890)
    |> Path.join("bin/open890_ft8_decoder")
    |> to_string()
  end
end
