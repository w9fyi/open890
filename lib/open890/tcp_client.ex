defmodule Open890.TCPClient do
  use GenServer
  require Logger
  alias Open890.RTP
  alias Open890.Extract

  @socket_opts [
    :binary,
    active: true,
    exit_on_close: true,
    send_timeout: 1000,
    send_timeout_close: true
  ]
  @connect_timeout_ms 5000
  @audio_tx_socket_dst_port 60001
  @audio_tx_socket_src_port 60002

  @enable_audio_scope true
  @enable_band_scope true

  alias Open890.{ConnectionCommands, RadioConnection, RadioState}
  alias Open890.KNS.User

  def start_link(%RadioConnection{id: id} = args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(id))
  end

  def via_tuple(connection_id) do
    {:via, Registry, {:radio_connection_registry, {:tcp, connection_id}}}
  end

  @impl true
  def init(%RadioConnection{} = connection) do
    radio_username = connection.user_name
    radio_password = connection.password
    radio_user_is_admin = connection.user_is_admin

    kns_user =
      User.build()
      |> User.username(radio_username)
      |> User.password(radio_password)
      |> User.is_admin(radio_user_is_admin)

    send(self(), :connect_socket)

    configured_tx_mic_gain =
      Application.get_env(:open890, __MODULE__, [])
      |> Keyword.get(:tx_mic_gain, 1.0)

    tx_mic_gain =
      connection
      |> Map.get(:local_tx_input_trim)
      |> case do
        nil -> configured_tx_mic_gain
        value -> value
      end
      |> normalize_tx_mic_gain()

    {:ok,
     %{
       connection: connection,
       kns_user: kns_user,
       radio_state: %RadioState{},
       socket: nil,
       audio_tx_socket: nil,
       audio_tx_seq_num: 1,
       tx_mic_gain: tx_mic_gain
     }}
  end

  @impl true
  def handle_call(:get_radio_state, _from, state) do
    {:reply, {:ok, state.radio_state}, state}
  end

  # Server API
  @impl true
  def handle_cast({:send_command, cmd}, state) do
    state.socket |> send_command(cmd)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_audio, data}, state) do
    case list_to_pcm16le(data) do
      nil -> {:noreply, state}
      pcm16le -> {:noreply, send_mic_frame(state, pcm16le)}
    end
  end

  @impl true
  def handle_cast({:send_audio_pcm16, pcm16le}, state) when is_binary(pcm16le) do
    {:noreply, send_mic_frame(state, pcm16le)}
  end

  @impl true
  def handle_cast({:set_tx_mic_gain, tx_mic_gain}, state) do
    normalized = normalize_tx_mic_gain(tx_mic_gain)
    Logger.info("Updated local TX input trim to #{normalized}")
    {:noreply, %{state | tx_mic_gain: normalized}}
  end

  defp send_mic_frame(
         %{connection: %{ip_address: ip_address}, audio_tx_socket: audio_tx_socket} = state,
         pcm16le
       )
       when is_binary(ip_address) and ip_address != "" and is_port(audio_tx_socket) and
              is_binary(pcm16le) do
    frame = normalize_pcm16le_frame(pcm16le)
    packet = make_tx_voip_packet(frame, state.audio_tx_seq_num, state.tx_mic_gain)

    case :gen_udp.send(
           audio_tx_socket,
           String.to_charlist(ip_address),
           @audio_tx_socket_dst_port,
           packet
         ) do
      :ok ->
        %{state | audio_tx_seq_num: state.audio_tx_seq_num + 1}

      {:error, reason} ->
        Logger.warn("Unable to send mic frame: #{inspect(reason)}")
        state
    end
  end

  defp send_mic_frame(state, _pcm16le), do: state

  defp make_tx_voip_packet(frame_pcm16le, seq_num, tx_mic_gain) do
    frame_pcm16le
    |> encode_tx_payload(tx_mic_gain)
    |> RTP.make_packet(seq_num)
  end

  defp encode_tx_payload(frame_pcm16le, tx_mic_gain) do
    for <<sample::signed-little-16 <- frame_pcm16le>>, into: <<>> do
      scaled = scale_sample(sample, tx_mic_gain)
      unsigned = scaled + 32_768
      <<unsigned::unsigned-big-16>>
    end
  end

  defp list_to_pcm16le(data) when is_list(data) do
    data
    |> Enum.take(320)
    |> Enum.reduce(<<>>, fn sample, acc ->
      <<acc::binary, clamp_sample(sample)::signed-little-16>>
    end)
    |> normalize_pcm16le_frame()
  end

  defp list_to_pcm16le(_), do: nil

  defp normalize_pcm16le_frame(frame_pcm16le) when byte_size(frame_pcm16le) == 640,
    do: frame_pcm16le

  defp normalize_pcm16le_frame(frame_pcm16le) when byte_size(frame_pcm16le) > 640,
    do: binary_part(frame_pcm16le, 0, 640)

  defp normalize_pcm16le_frame(frame_pcm16le) do
    missing = 640 - byte_size(frame_pcm16le)
    <<frame_pcm16le::binary, 0::size(missing)-unit(8)>>
  end

  defp scale_sample(sample, tx_mic_gain) do
    sample
    |> Kernel.*(tx_mic_gain)
    |> round()
    |> clamp_sample()
  end

  defp clamp_sample(sample) when is_integer(sample), do: min(32_767, max(-32_768, sample))
  defp clamp_sample(sample) when is_float(sample), do: sample |> round() |> clamp_sample()
  defp clamp_sample(_sample), do: 0

  defp normalize_tx_mic_gain(gain) when is_float(gain), do: min(8.0, max(0.01, gain))
  defp normalize_tx_mic_gain(gain) when is_integer(gain), do: normalize_tx_mic_gain(gain * 1.0)

  defp normalize_tx_mic_gain(gain) when is_binary(gain) do
    case Float.parse(gain) do
      {parsed, _} -> normalize_tx_mic_gain(parsed)
      :error -> 1.0
    end
  end

  defp normalize_tx_mic_gain(_), do: 1.0

  def handle_info({:tcp, _socket, _msg}, {:noreply, %{connection: connection} = state}) do
    Logger.error("Got TCP :noreply state")

    broadcast_connection_state(connection, {:down, :tcp_noreply})
    {:stop, :shutdown, state}
  end

  def handle_info({:tcp, _socket, _msg}, {:noreply, other_state}) do
    Logger.error("Got TCP :noreply with invalid state: #{inspect(other_state)}")
    {:stop, :shutdown, other_state}
  end

  # networking
  @impl true
  def handle_info({:tcp, socket, msg}, %{socket: socket} = state) do
    result =
      msg
      |> String.split(";")
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while(state, fn single_message, acc ->
        case handle_msg(single_message, acc) do
          {:stop, reason, new_state} ->
            {:halt, {:stop, reason, new_state}}

          {:noreply, %{} = new_state} ->
            {:cont, new_state}

          %{} = new_state ->
            {:cont, new_state}

          other ->
            Logger.error(
              "Unexpected handle_msg return for #{inspect(single_message)}: #{inspect(other)}"
            )

            {:cont, acc}
        end
      end)

    case result do
      {:stop, reason, new_state} ->
        {:stop, reason, new_state}

      %{} = new_state ->
        {:noreply, new_state}
    end
  end

  def handle_info({:tcp_closed, _socket}, %{connection: connection} = state) do
    Logger.warn("TCP socket closed.")

    broadcast_connection_state(connection, {:down, :tcp_closed})

    {:stop, :shutdown, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warn("TCP socket closed with invalid state: #{inspect(state)}")
    {:stop, :shutdown, state}
  end

  def handle_info(:connect_socket, state) do
    ip_address = state.connection.ip_address |> String.to_charlist()
    tcp_port = RadioConnection.tcp_port(state.connection)

    :gen_tcp.connect(ip_address, tcp_port, @socket_opts, @connect_timeout_ms)
    |> case do
      {:ok, socket} ->
        Logger.info("Established TCP socket with radio on port #{tcp_port}")

        state = %{state | socket: socket}
        broadcast_connection_state(state.connection, :up)
        self() |> send(:login_radio)

        with {:ok, audio_tx_socket} <- :gen_udp.open(@audio_tx_socket_src_port) do
          {:noreply, %{state | audio_tx_socket: audio_tx_socket}}
        else
          other ->
            Logger.warn("Error opening audio TX UDP socket: #{inspect(other)}")
            {:noreply, state}
        end

      {:error, reason} ->
        broadcast_connection_state(state.connection, {:down, reason})

        Logger.error(
          "Unable to connect to radio: #{inspect(reason)}. Connection: #{inspect(state.connection)}"
        )

        {:stop, :shutdown, state}
    end
  end

  def handle_info(:login_radio, %{socket: socket} = state) do
    socket |> send_command("##CN")
    {:noreply, state}
  end

  # radio commands
  def handle_info(:enable_audioscope, %{socket: socket} = state) do
    Logger.info("Enabling audio scope via LAN")
    socket |> send_command("DD11")

    {:noreply, state}
  end

  def handle_info(:enable_bandscope, %{socket: socket} = state) do
    Logger.info("Enabling LAN bandscope")

    # low cycle
    # socket |> send_command("DD03")

    # medium-cycle
    # socket |> send_command("DD02")

    # high-cycle
    socket |> send_command("DD01")

    {:noreply, state}
  end

  def handle_info(:enable_voip, state) do
    Logger.info("\n\n**** Enabling HQ VOIP stream\n\n")
    # high quality
    state.socket |> send_command("##VP1")
    # state.socket |> send_command("##VP2") # low quality

    {:noreply, state}
  end

  def handle_info(:query_active_receiver, state) do
    state.socket |> send_command("FR")
    {:noreply, state}
  end

  def handle_info(:get_initial_state, %{connection: connection} = state) do
    connection |> ConnectionCommands.get_initial_state()
    {:noreply, state}
  end

  def handle_info(:enable_auto_info, state) do
    state.socket |> send_command("AI2")
    {:noreply, state}
  end

  def handle_info(:send_keepalive, %{socket: socket} = state) do
    schedule_ping()

    socket |> send_command("PS")

    {:noreply, state}
  end

  def handle_msg("##CN0", %{socket: socket} = state) do
    msg =
      "Unable to connect to radio: The KNS connection may already be in use by another application"

    Logger.warn(msg)
    broadcast_connection_state(state.connection, {:down, :kns_in_use})

    if socket, do: :gen_tcp.close(socket)

    {:stop, :shutdown, state}
  end

  # connection allowed response
  def handle_msg("##CN1", %{socket: socket, kns_user: kns_user} = state) do
    login = kns_user |> User.to_login()

    socket |> send_command("##ID" <> login)
    state
  end

  # login successful response
  def handle_msg("##ID1", state) do
    Logger.info("signed in, scheduling first ping")
    schedule_ping()

    if @enable_audio_scope, do: send(self(), :enable_audioscope)
    if @enable_band_scope, do: send(self(), :enable_bandscope)

    send(self(), :enable_auto_info)
    send(self(), :query_active_receiver)
    send(self(), :get_initial_state)

    state
  end

  def handle_msg("##ID0", %{connection: connection, socket: socket} = state) do
    Logger.warn("Error connecting to radio: Incorrect username or password")
    broadcast_connection_state(connection, {:down, :bad_credentials})

    if socket, do: :gen_tcp.close(socket)

    {:stop, :shutdown, state}
  end

  def handle_msg("PS" <> _level = msg, %{connection: connection} = state) do
    power_state = Extract.power_state(msg)
    RadioConnection.broadcast_power_state(connection, power_state)

    state
  end

  # login enabled response
  def handle_msg("##UE1", state), do: state

  # everything under here

  # # bandscope data speed high response
  # def handle_msg("DD01", state), do: state

  # # filter scope LAN/high cycle respnose
  # def handle_msg("DD11", state), do: state

  def handle_msg("BSD", %{connection: connection} = state) do
    RadioConnection.broadcast_band_scope_cleared(connection)

    state
  end

  def handle_msg(
        msg,
        %{socket: _socket, connection: connection, radio_state: radio_state} = state
      )
      when is_binary(msg) do
    cond do
      # high speed filter/audio scope response
      msg |> String.starts_with?("##DD3") ->
        audio_scope_data =
          msg
          |> String.trim_leading("##DD3")
          |> parse_scope_data()

        RadioConnection.broadcast_audio_scope(connection, audio_scope_data)

        state

      # high speed band scope data response
      msg |> String.starts_with?("##DD2") ->
        band_scope_data =
          msg
          |> String.trim_leading("##DD2")
          |> parse_scope_data()

        # band_scope_data |> Enum.count() |> IO.inspect(label: "band scope data length")

        ## If expand mode is on:
        # For spans 5-100 khz, only render the middle 1/3 of samples received. For 200khz, render the middle 1/2. For 500 khz, just render all of what is received.

        band_scope_data =
          if radio_state.band_scope_expand do
            cond do
              radio_state.band_scope_span <= 100 ->
                # take middle 1/3 of samples, and triple them
                band_scope_data
                |> Enum.slice(213..427)
                |> Enum.flat_map(fn x -> [x, x, x] end)

              radio_state.band_scope_span == 200 ->
                # take the middle 1/2 and double them
                band_scope_data
                |> Enum.slice(160..500)
                |> Enum.flat_map(fn x -> [x, x] end)

              200 ->
                # spans over 200khz, just render everything
                band_scope_data
            end
          else
            band_scope_data
          end

        RadioConnection.broadcast_band_scope(connection, band_scope_data)

        state

      true ->
        # otherwise, broadcast the new radio state to the liveview
        if !(msg |> String.starts_with?("SM0")) do
          Logger.info("[DN] #{inspect(msg)}")
        end

        if msg |> String.starts_with?("BS31") do
          connection |> ConnectionCommands.get_band_scope_limits()
        end

        radio_state = radio_state |> RadioState.dispatch(msg)

        if msg |> String.starts_with?("MV") do
          # re-retrieve the operating mode when toggling between M/V
          # This fixes an issue where the audio scope filter edges disappear
          # When toggling M/V
          ConnectionCommands.get_active_mode(connection)
        end

        # lock state
        if msg |> String.starts_with?("LK") do
          lock_state = msg |> String.ends_with?("1")
          connection |> RadioConnection.broadcast_lock_state(lock_state)
        end

        if ["FA", "FB", "OM0", "FT"] |> Enum.any?(&String.starts_with?(msg, &1)) do
          Open890.Cloudlog.update(connection, radio_state)
        end

        # (radio_state.band_scope_mode == :center && radio_state.rit_enabled && msg |> String.starts_with?("RF") )
        if (msg |> String.starts_with?("FA") && radio_state.active_receiver == :a) ||
             (msg |> String.starts_with?("FB") && radio_state.active_receiver == :b) do
          if radio_state.band_scope_edges do
            {low, high} = radio_state.band_scope_edges
            delta = radio_state.active_frequency_delta
            active_receiver = radio_state.active_receiver

            RadioConnection.broadcast_freq_delta(connection, %{
              delta: delta,
              vfo: active_receiver,
              bs: %{low: low, high: high}
            })
          end
        end

        # finally, broadcast the entire radio state to the views
        RadioConnection.broadcast_radio_state(connection, radio_state)
        %{state | radio_state: radio_state}
    end
  end

  def broadcast_connection_state(%RadioConnection{} = connection, state) do
    RadioConnection.broadcast_connection_state(connection, state)
  end

  defp schedule_ping do
    Process.send_after(self(), :send_keepalive, 5000)
  end

  defp send_command(socket, msg) when is_binary(msg) do
    cmd = msg <> ";"

    if cmd != "PS;", do: Logger.info("[UP] #{inspect(cmd)}")

    socket |> :gen_tcp.send(cmd)

    socket
  end

  defp parse_scope_data(msg) do
    msg
    |> String.codepoints()
    |> Enum.chunk_every(2)
    |> Enum.map(&Enum.join/1)
    |> Enum.map(fn value ->
      Integer.parse(value, 16) |> elem(0)
    end)
  end
end
