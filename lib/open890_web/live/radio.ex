defmodule Open890Web.Live.Radio do
  require Logger

  use Open890Web, :live_view
  use Open890Web.Live.RadioLiveEventHandling

  alias Phoenix.Socket.Broadcast

  alias Open890.{
    ConnectionCommands,
    Extract,
    FrequencyEntryParser,
    KeyboardEntryState,
    RadioConnection,
    RNNoisePort,
    FT8DecoderPort,
    RadioState,
    UserMarker
  }

  alias Open890Web.Live.RadioSocketState

  alias Open890Web.Components.{
    AtuIndicator,
    AudioScope,
    BandScope,
    BusyTxIndicator,
    FineButton,
    LockButton,
    Meter,
    MhzButton,
    RitXit,
    Slider,
    SplitButton,
    VFODisplayComponent,
    VoipButtons
  }

  import Open890Web.Components.Buttons

  @ft8_reference_tone_hz 1500.0
  @ft8_band_presets [
    %{id: "160m", label: "160m - 1.840", freq_hz: 1_840_000},
    %{id: "80m", label: "80m - 3.573", freq_hz: 3_573_000},
    %{id: "60m", label: "60m - 5.357", freq_hz: 5_357_000},
    %{id: "40m", label: "40m - 7.074", freq_hz: 7_074_000},
    %{id: "30m", label: "30m - 10.136", freq_hz: 10_136_000},
    %{id: "20m", label: "20m - 14.074", freq_hz: 14_074_000},
    %{id: "17m", label: "17m - 18.100", freq_hz: 18_100_000},
    %{id: "15m", label: "15m - 21.074", freq_hz: 21_074_000},
    %{id: "12m", label: "12m - 24.915", freq_hz: 24_915_000},
    %{id: "10m", label: "10m - 28.074", freq_hz: 28_074_000},
    %{id: "6m", label: "6m - 50.313", freq_hz: 50_313_000}
  ]

  @impl true
  def mount(%{"id" => connection_id} = params, _session, socket) do
    Logger.info("LiveView mount: params: #{inspect(params)}")

    if connected?(socket) do
      RadioConnection.subscribe(Open890.PubSub, connection_id)
      Phoenix.PubSub.subscribe(Open890.PubSub, "radio:ft8")
    end

    socket =
      socket
      |> assign(RadioSocketState.initial_state())
      |> assign(:software_nr_enabled, RNNoisePort.enabled?())
      |> assign(:ft8_status, FT8DecoderPort.status())
      |> assign(:ft8_enabled, FT8DecoderPort.enabled?())
      |> assign(:ft8_band_presets, @ft8_band_presets)
      |> assign(:ft8_band_preset, default_ft8_band_id())

    socket =
      with {:ok, file} <- File.read("config/config.toml"),
           {:ok, config} <- Toml.decode(file) do
        macros = config |> get_in(["ui", "macros"]) || []
        socket |> assign(:__ui_macros, macros)
      else
        reason ->
          Logger.info(
            "Could not load config/config.toml: #{inspect(reason)}. This is not currently an error."
          )

          socket
      end

    socket =
      RadioConnection.find(connection_id)
      |> case do
        {:ok, %RadioConnection{} = connection} ->
          Logger.info("Found connection: #{connection_id}")

          socket = socket |> assign(:radio_connection, connection)

          socket =
            if params["debug"] do
              socket |> assign(:debug, true)
            else
              socket
            end

          socket =
            connection
            |> RadioConnection.process_exists?()
            |> case do
              true ->
                connection |> ConnectionCommands.get_initial_state()
                socket |> assign(:connection_state, :up)

              _ ->
                socket
            end

          socket

        {:error, reason} ->
          Logger.warn("Could not find radio connection id: #{connection_id}: #{inspect(reason)}")
          socket |> redirect(to: "/connections")
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_tab = params["panelTab"] || socket.assigns.active_tab || "txrx"

    panel_open = params |> Map.get("panel", "true") == "true"

    socket =
      socket
      |> assign(active_tab: selected_tab)
      |> assign(left_panel_open: panel_open)

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Broadcast{event: "scope_data", payload: %{payload: audio_scope_data}}, socket) do
    {:noreply,
     socket
     |> push_event("scope_data", %{scope_data: audio_scope_data})
     |> assign(:audio_scope_data, audio_scope_data)}
  end

  @impl true
  def handle_info(
        %Broadcast{event: "band_scope_data", payload: %{payload: band_scope_data}},
        socket
      ) do
    {:noreply,
     socket
     |> push_event("band_scope_data", %{scope_data: band_scope_data})
     |> assign(:band_scope_data, band_scope_data)}
  end

  @impl true
  def handle_info(%Broadcast{event: "lock_state", payload: locked}, socket) do
    {:noreply, socket |> push_event("lock_state", %{locked: locked})}
  end

  @impl true
  def handle_info(%Broadcast{event: "band_scope_cleared"}, socket) do
    {:noreply, socket |> push_event("clear_band_scope", %{})}
  end

  @impl true
  def handle_info(%Broadcast{event: "radio_state_data", payload: %{msg: radio_state}}, socket) do
    formatted_frequency =
      radio_state
      |> RadioState.effective_active_frequency()
      |> RadioViewHelpers.format_raw_frequency()

    formatted_mode =
      radio_state
      |> RadioState.effective_active_mode()
      |> RadioViewHelpers.format_mode()

    page_title = "#{formatted_frequency} - #{formatted_mode}"

    socket =
      assign(socket, :radio_state, radio_state)
      |> assign(:page_title, page_title)

    {:noreply, socket}
  end

  # Connection state messages
  def handle_info(
        %Broadcast{event: "connection_state", payload: %{id: _id, state: connection_state}} =
          payload,
        socket
      ) do
    Logger.debug("Bandscope LV: RX connection_state: #{inspect(payload)}")

    {:noreply, assign(socket, :connection_state, connection_state)}
  end

  def handle_info(%Broadcast{event: "freq_delta", payload: payload}, socket) do
    socket =
      if socket.assigns.radio_state.band_scope_mode == :center do
        socket |> push_event("freq_delta", payload)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "power_state", payload: _payload}, socket) do
    # ignore power state broadcasts for now
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "ft8_decode", payload: payload}, socket) do
    decodes =
      [payload | socket.assigns.ft8_decodes]
      |> Enum.take(25)

    {:noreply, assign(socket, :ft8_decodes, decodes)}
  end

  def handle_info(%Broadcast{event: "ft8_status", payload: payload}, socket) do
    active = Map.get(payload, :active, Map.get(payload, "active", false))
    enabled = Map.get(payload, :enabled, Map.get(payload, "enabled", false))

    {:noreply,
     socket
     |> assign(:ft8_status, payload)
     |> assign(:ft8_enabled, active || enabled)}
  end

  def handle_info(%Broadcast{} = bc, socket) do
    Logger.warn("Unknown broadcast: #{inspect(bc)}")

    {:noreply, socket}
  end

  # received by Task.async
  def handle_info({_ref, :ok}, socket) do
    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  def handle_info(:expire_keyboard_state, socket) do
    Logger.info(":expire_keyboard_state")

    case socket.assigns.keyboard_entry_timer do
      nil ->
        Logger.info("expire_keyboard_state: wanted to cancel a nil timer")

      timer ->
        Logger.info("expire_keyboard_state: canceling timer")
        Process.cancel_timer(timer)

        Logger.info("expire_keyboard_state: transition to KeyboardEntryState.Normal")
    end

    # Always transition to normal
    socket =
      socket
      |> assign(keyboard_entry_state: KeyboardEntryState.Normal)
      |> assign(keyboard_entry_timer: nil)

    {:noreply, socket}
  end

  def handle_event(
        "toggle_mic",
        _params,
        %{assigns: %{voip_mic_enabled: voip_mic_enabled}} = socket
      ) do
    enabled = !voip_mic_enabled
    Logger.info("voip mic enabled: #{enabled}")

    socket =
      socket
      |> assign(:voip_mic_enabled, enabled)
      |> push_event("toggle_mic", %{enabled: enabled})

    {:noreply, socket}
  end

  def handle_event("voip_mic_enabled", %{"state" => state} = _params, socket) do
    socket = socket |> assign(:voip_mic_enabled, state)

    {:noreply, socket}
  end

  def handle_event("toggle_software_nr", _params, socket) do
    enabled = !socket.assigns.software_nr_enabled
    updated_enabled = RNNoisePort.set_enabled(enabled)

    socket =
      socket
      |> assign(:software_nr_enabled, updated_enabled)

    {:noreply, socket}
  end

  def handle_event("toggle_ft8_decoder", _params, socket) do
    enabled = !socket.assigns.ft8_enabled
    updated_enabled = FT8DecoderPort.set_enabled(enabled)

    socket =
      socket
      |> assign(:ft8_enabled, updated_enabled)
      |> assign(:ft8_status, FT8DecoderPort.status())

    {:noreply, socket}
  end

  def handle_event("set_ft8_band", %{"band" => band_id}, socket) do
    case ft8_preset_by_id(band_id) do
      nil ->
        {:noreply, socket |> put_ft8_error("Unknown FT8 band preset")}

      _preset ->
        {:noreply,
         socket
         |> assign(:ft8_band_preset, band_id)
         |> clear_ft8_error()}
    end
  end

  def handle_event("start_ft8", _params, socket) do
    with %{freq_hz: target_hz, label: preset_label} <-
           ft8_preset_by_id(socket.assigns.ft8_band_preset),
         {:ok, tune_info} <- tune_active_vfo(socket, target_hz) do
      updated_enabled = FT8DecoderPort.set_enabled(true)

      socket =
        socket
        |> clear_ft8_error()
        |> assign(:ft8_enabled, updated_enabled)
        |> assign(:ft8_status, FT8DecoderPort.status())
        |> assign(
          :ft8_last_tuned,
          Map.merge(tune_info, %{preset_label: preset_label, delta_hz: nil})
        )

      {:noreply, socket}
    else
      nil ->
        {:noreply, socket |> put_ft8_error("Unknown FT8 band preset")}

      {:error, :no_active_receiver} ->
        {:noreply, socket |> put_ft8_error("No active receiver selected for FT8 tune")}

      _ ->
        {:noreply, socket |> put_ft8_error("Unable to start FT8")}
    end
  end

  def handle_event("stop_ft8", _params, socket) do
    updated_enabled = FT8DecoderPort.set_enabled(false)

    socket =
      socket
      |> assign(:ft8_enabled, updated_enabled)
      |> assign(:ft8_status, FT8DecoderPort.status())

    {:noreply, socket}
  end

  def handle_event("clear_ft8_decodes", _params, socket) do
    {:noreply, assign(socket, :ft8_decodes, [])}
  end

  def handle_event("tune_ft8_decode", %{"freq" => decode_freq}, socket) do
    with {freq_hz, _rest} <- Float.parse(to_string(decode_freq)),
         {:ok, tune_info} <- tune_to_ft8_decode(socket, freq_hz) do
      socket =
        socket
        |> clear_ft8_error()
        |> assign(:ft8_last_tuned, tune_info)

      {:noreply, socket}
    else
      {:error, :no_active_frequency} ->
        {:noreply, socket |> put_ft8_error("No active frequency available to tune")}

      {:error, :no_active_receiver} ->
        {:noreply, socket |> put_ft8_error("No active receiver selected for FT8 tune")}

      _ ->
        {:noreply, socket |> put_ft8_error("Invalid FT8 decode frequency")}
    end
  end

  def handle_event("direct_frequency_entry", %{"freq" => freq} = params, socket) do
    Logger.warn("frequency entry: #{inspect(params)}")
    conn = socket.assigns.radio_connection

    parsed_freq = FrequencyEntryParser.parse(freq)

    case socket.assigns.radio_state.active_receiver do
      :a ->
        conn |> ConnectionCommands.cmd("FA#{parsed_freq}")

      :b ->
        conn |> ConnectionCommands.cmd("FB#{parsed_freq}")
    end

    {:noreply, socket}
  end

  def handle_event("toggle_panel", _params, socket) do
    new_state = !socket.assigns.left_panel_open

    radio_conn = socket.assigns.radio_connection

    new_params = %{
      panel: new_state,
      panelTab: socket.assigns.active_tab
    }

    socket =
      socket
      |> push_patch(to: Routes.radio_path(socket, :show, radio_conn.id, new_params))

    {:noreply, socket}
  end

  def handle_event("toggle_band_selector", _params, socket) do
    socket =
      if socket.assigns.display_band_selector do
        close_modals(socket)
      else
        open_band_selector(socket)
      end

    {:noreply, socket}
  end

  def handle_event("set_tab", %{"tab" => tab_name}, socket) do
    Logger.info("set_tab: #{inspect(tab_name)}")

    radio_conn = socket.assigns.radio_connection

    new_params = %{
      panel: socket.assigns.left_panel_open,
      panelTab: tab_name
    }

    socket =
      socket
      |> push_patch(to: Routes.radio_path(socket, :show, radio_conn.id, new_params))

    {:noreply, socket}
  end

  def handle_event("step_tune_up", %{"stepSize" => step_size} = _params, socket) do
    conn = socket.assigns.radio_connection

    conn |> ConnectionCommands.cmd("FC0#{step_size}")

    {:noreply, socket}
  end

  def handle_event("step_tune_down", %{"stepSize" => step_size} = _params, socket) do
    conn = socket.assigns.radio_connection

    conn |> ConnectionCommands.cmd("FC1#{step_size}")
    {:noreply, socket}
  end

  def handle_event("window_keydown", %{"key" => key} = params, socket) do
    Logger.debug("live/radio.ex: window_keydown: #{inspect(params)}")

    ctrl_down = event_flag(params, "ctrlKey")
    shift_down = event_flag(params, "shiftKey")
    alt_down = event_flag(params, "altKey")
    meta_down = event_flag(params, "metaKey")

    conn = socket.assigns.radio_connection
    normalized_key = normalize_key(key)

    socket =
      cond do
        ctrl_down and shift_down and normalized_key in ["l", "u", "c", "a", "f"] ->
          conn |> ConnectionCommands.cmd(mode_shortcut_cmd(normalized_key))
          socket

        meta_down and shift_down and normalized_key == "e" ->
          open_band_selector(socket)

        alt_down and shift_down and !socket.assigns.ptt_hotkey_active and
            socket.assigns.radio_state.tx_state == :off ->
          conn |> ConnectionCommands.cmd("TX0")
          socket |> assign(:ptt_hotkey_active, true)

        true ->
          case key do
            "]" ->
              conn |> ConnectionCommands.freq_change(:up)

            "[" ->
              conn |> ConnectionCommands.freq_change(:down)

            _ ->
              :ok
          end

          socket
      end

    {:noreply, socket}
  end

  def handle_event("window_keydown", params, socket) do
    Logger.debug("live/radio.ex: window_keydown: #{inspect(params)}")

    {:noreply, socket}
  end

  # close any open modals
  def handle_event("window_keyup", %{"key" => "Escape"} = _params, socket) do
    {:noreply, close_modals(socket)}
  end

  def handle_event("window_keyup", %{"key" => key} = params, socket) do
    Logger.debug("live/radio.ex: window_keyup: #{inspect(params)}")

    alt_shift_down = event_flag(params, "altKey") && event_flag(params, "shiftKey")

    socket =
      if socket.assigns.ptt_hotkey_active && !alt_shift_down do
        socket.assigns.radio_connection |> ConnectionCommands.cmd("RX")
        socket |> assign(:ptt_hotkey_active, false)
      else
        socket
      end

    socket = handle_keyboard_state(socket.assigns.keyboard_entry_state, key, socket)

    {:noreply, socket}
  end

  def handle_event("window_keyup", params, socket) do
    Logger.debug("window_keyup: #{inspect(params)}")

    {:noreply, socket}
  end

  def handle_event("start_connection", _params, socket) do
    RadioConnection.start(socket.assigns.radio_connection.id)

    {:noreply, socket}
  end

  def handle_event("stop_connection", _params, socket) do
    RadioConnection.stop(socket.assigns.radio_connection.id)

    {:noreply, socket}
  end

  def handle_event("dimmer_clicked", _params, socket) do
    {:noreply, close_modals(socket)}
  end

  def handle_event("run_macro", %{"name" => macro_name} = _params, socket) do
    Logger.debug("Running macro: #{inspect(macro_name)}")

    commands =
      socket.assigns.__ui_macros
      |> Enum.find(fn x -> x["label"] == macro_name end)
      |> case do
        %{"commands" => commands} ->
          commands

        _ ->
          []
      end

    case commands do
      [] ->
        :ok

      commands ->
        conn = socket.assigns.radio_connection

        Task.async(fn ->
          commands
          |> Enum.each(fn command ->
            Logger.debug("  Command: #{inspect(command)}")

            cond do
              command |> String.starts_with?("DE") ->
                delay_ms = Extract.delay_msec(command)

                Logger.debug(
                  "Processing special DELAY macro #{inspect(command)} for #{delay_ms} ms"
                )

                Process.sleep(delay_ms)

              true ->
                conn |> ConnectionCommands.cmd(command)
                Process.sleep(100)
            end
          end)
        end)

        :ok
    end

    {:noreply, socket}
  end

  def handle_event("adjust_filter", params, socket) do
    Logger.info("adjust_filter: #{inspect(params)}")

    filter_state = socket.assigns.radio_state.filter_state
    connection = socket.assigns.radio_connection

    lo_width_passband_id = filter_state.lo_passband_id
    hi_shift_passband_id = filter_state.hi_passband_id

    is_up = params["dir"] == "up"

    if params["shift"] do
      # adjust shift
      new_passband_id =
        if is_up do
          hi_shift_passband_id + 1
        else
          hi_shift_passband_id - 1
        end
        |> to_string()
        |> String.pad_leading(4, "0")

      connection |> RadioConnection.cmd("SH#{new_passband_id}")
    else
      # width
      new_passband_id =
        if is_up do
          lo_width_passband_id + 1
        else
          lo_width_passband_id - 1
        end
        |> to_string()
        |> String.pad_leading(3, "0")

      connection |> RadioConnection.cmd("SL#{new_passband_id}")
    end

    {:noreply, socket}
  end

  def handle_event("delete_user_marker", %{"id" => marker_id} = _params, socket) do
    Logger.info("delete_user_marker, id: #{inspect(marker_id)}")

    conn = socket.assigns.radio_connection
    RadioConnection.delete_user_marker(conn, marker_id)

    # This block of code should go into RadioConnection.delete_user_marker(),
    # It should return the list of remaining markers for the socket.
    updated_markers =
      socket.assigns.markers
      |> Enum.reject(fn %UserMarker{id: id} ->
        id == marker_id
      end)

    socket = assign(socket, :markers, updated_markers)

    {:noreply, socket}
  end

  def handle_event("power_level_changed", %{"value" => power_level} = _params, socket) do
    Logger.info("power_level_changed: #{inspect(power_level)}")

    power_level = (power_level / 255.0 * 100) |> round()

    socket.assigns.radio_connection
    |> ConnectionCommands.set_power_level(power_level)

    {:noreply, socket}
  end

  def handle_event("mic_audio", params, socket) do
    mic_data =
      params["data"]
      |> String.split(" ")
      |> Enum.map(&String.to_integer/1)

    socket.assigns.radio_connection
    |> RadioConnection.send_mic_audio(mic_data)

    {:noreply, socket}
  end

  def handle_event("mic_audio_frame", %{"pcm16le_b64" => payload_b64}, socket)
      when is_binary(payload_b64) do
    case Base.decode64(payload_b64) do
      {:ok, pcm16le} when is_binary(pcm16le) ->
        socket.assigns.radio_connection
        |> RadioConnection.send_mic_audio_frame(pcm16le)

      :error ->
        Logger.warn("Invalid mic_audio_frame payload (base64 decode failed)")
    end

    {:noreply, socket}
  end

  def handle_event(event, params, socket) do
    Logger.warn("Live.Radio: Unknown event: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  defp tune_to_ft8_decode(socket, decode_freq_hz) do
    radio_state = socket.assigns.radio_state

    active_frequency_hz = RadioState.effective_active_frequency(radio_state)

    if is_integer(active_frequency_hz) and active_frequency_hz > 0 do
      delta_hz = round(decode_freq_hz - @ft8_reference_tone_hz)
      target_hz = max(active_frequency_hz + delta_hz, 0)

      with {:ok, tune_info} <- tune_active_vfo(socket, target_hz) do
        {:ok, Map.merge(tune_info, %{decode_freq_hz: round(decode_freq_hz), delta_hz: delta_hz})}
      end
    else
      {:error, :no_active_frequency}
    end
  end

  defp tune_active_vfo(socket, target_hz) when is_integer(target_hz) and target_hz >= 0 do
    radio_state = socket.assigns.radio_state
    connection = socket.assigns.radio_connection
    target = target_hz |> Integer.to_string() |> String.pad_leading(11, "0")

    case radio_state.active_receiver do
      :a ->
        connection |> ConnectionCommands.cmd("FA#{target}")
        {:ok, %{target_hz: target_hz}}

      :b ->
        connection |> ConnectionCommands.cmd("FB#{target}")
        {:ok, %{target_hz: target_hz}}

      _ ->
        {:error, :no_active_receiver}
    end
  end

  defp ft8_preset_by_id(id) when is_binary(id) do
    Enum.find(@ft8_band_presets, fn preset -> preset.id == id end)
  end

  defp default_ft8_band_id do
    @ft8_band_presets
    |> Enum.find(%{id: "20m"}, fn preset -> preset.id == "20m" end)
    |> Map.fetch!(:id)
  end

  defp put_ft8_error(socket, message) do
    ft8_status =
      socket.assigns.ft8_status
      |> Map.put(:last_error, message)

    socket |> assign(:ft8_status, ft8_status)
  end

  defp clear_ft8_error(socket) do
    ft8_status =
      socket.assigns.ft8_status
      |> Map.put(:last_error, nil)

    socket |> assign(:ft8_status, ft8_status)
  end

  defp close_modals(socket) do
    socket
    |> assign(%{
      display_band_selector: false,
      keyboard_entry_state: KeyboardEntryState.Normal,
      display_screen_id: 0
    })
  end

  defp open_band_selector(socket) do
    socket
    |> assign(:keyboard_entry_state, KeyboardEntryState.DirectFrequencyEntry)
    |> assign(:display_band_selector, true)
  end

  def radio_classes(debug \\ false) do
    classes = "ui grid noselect"

    if debug do
      classes <> " debug"
    else
      classes
    end
  end

  def panel_classes(flag) do
    if flag do
      "bandscopePanel left"
    else
      "bandscopePanel left hidden"
    end
  end

  def tab_classes(name, var) do
    if name == var do
      "item active"
    else
      "item"
    end
  end

  def tab_panel_classes(name, var) do
    if name == var do
      "ui tabs"
    else
      "ui tabs hidden"
    end
  end

  defp mode_shortcut_cmd("l"), do: "MD1"
  defp mode_shortcut_cmd("u"), do: "MD2"
  defp mode_shortcut_cmd("c"), do: "MD3"
  defp mode_shortcut_cmd("a"), do: "MD5"
  defp mode_shortcut_cmd("f"), do: "MD4"

  defp normalize_key(key) when is_binary(key) do
    key
    |> String.downcase()
    |> String.trim()
  end

  defp normalize_key(_), do: ""

  defp event_flag(params, field) do
    case Map.get(params, field) do
      true ->
        true

      "true" ->
        true

      1 ->
        true

      "1" ->
        true

      _ ->
        false
    end
  end

  defp handle_keyboard_state(KeyboardEntryState.DirectFrequencyEntry, _key, socket) do
    # FIXME: handle ESC here to close the modal?
    socket
  end

  defp handle_keyboard_state(KeyboardEntryState.Normal, key, socket) do
    radio_state = socket.assigns.radio_state
    conn = socket.assigns.radio_connection

    case key do
      "s" ->
        conn |> ConnectionCommands.toggle_split(radio_state)
        socket

      "m" ->
        Logger.info("transition keyboard state to PlaceMarker")
        timer = Process.send_after(self(), :expire_keyboard_state, 2000)

        socket
        |> assign(:keyboard_entry_state, KeyboardEntryState.PlaceMarker)
        |> assign(:keyboard_entry_timer, timer)

      "h" ->
        conn |> ConnectionCommands.band_scope_shift()
        socket

      "c" ->
        Logger.info("transition keyboard state to ClearMarkers")
        timer = Process.send_after(self(), :expire_keyboard_state, 2000)

        socket
        |> assign(:keyboard_entry_state, KeyboardEntryState.ClearMarkers)
        |> assign(:keyboard_entry_timer, timer)

      "t" ->
        conn |> ConnectionCommands.cw_tune()
        socket

      "=" ->
        conn |> ConnectionCommands.equalize_vfo()
        socket

      "\\" ->
        conn |> ConnectionCommands.toggle_vfo(radio_state)
        socket

      "Enter" ->
        open_band_selector(socket)

      _ ->
        socket
    end
  end

  defp handle_keyboard_state(KeyboardEntryState.PlaceMarker, key, socket) do
    radio_state = socket.assigns.radio_state

    case key do
      marker_key when marker_key in ["r", "g", "b", "m"] ->
        freq = RadioState.effective_active_frequency(radio_state)

        marker = UserMarker.create(freq)

        marker =
          case marker_key do
            "r" -> UserMarker.red(marker)
            "g" -> UserMarker.green(marker)
            "b" -> UserMarker.blue(marker)
            "m" -> UserMarker.white(marker)
          end

        socket = assign(socket, :markers, socket.assigns.markers ++ [marker])
        RadioConnection.add_user_marker(socket.assigns.radio_connection, marker)
        Logger.debug("Place marker: #{inspect(marker)}")

        if !is_nil(socket.assigns.keyboard_entry_timer) do
          Process.cancel_timer(socket.assigns.keyboard_entry_timer)
        end

        Logger.info("Transitioning to KeyboardEntryState.Normal")

        socket
        |> assign(:keyboard_entry_state, KeyboardEntryState.Normal)
        |> assign(:keyboard_entry_timer, nil)

      _ ->
        socket
    end
  end

  defp handle_keyboard_state(KeyboardEntryState.ClearMarkers, key, socket) do
    key_to_colors = %{
      "r" => :red,
      "g" => :green,
      "b" => :blue,
      "m" => :white
    }

    socket =
      case key do
        marker_key when marker_key in ["r", "g", "b", "c", "m"] ->
          existing_markers = socket.assigns.markers

          new_markers =
            Enum.reject(existing_markers, fn %UserMarker{color: color} ->
              if marker_key == "c" do
                true
              else
                color == key_to_colors[marker_key]
              end
            end)

          Logger.info("New markers: #{inspect(new_markers)}")

          assign(socket, :markers, new_markers)

        _ ->
          socket
      end

    Logger.info("Clear markers: canceling timer")

    if !is_nil(socket.assigns.keyboard_entry_timer) do
      Process.cancel_timer(socket.assigns.keyboard_entry_timer)
    end

    Logger.info("Clear markers: transitioning to KeyboardEntryState.Normal")

    socket
    |> assign(:keyboard_entry_state, KeyboardEntryState.Normal)
    |> assign(:keyboard_entry_timer, nil)
  end
end
