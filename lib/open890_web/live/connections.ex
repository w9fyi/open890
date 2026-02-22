defmodule Open890Web.Live.Connections do
  require Logger

  use Open890Web, :live_view

  alias Phoenix.Socket.Broadcast

  alias Open890.RadioConnection

  def mount(_params, _session, socket) do
    Logger.info("Connections live mounted")

    connections = RadioConnection.all()

    power_states =
      connections
      |> Enum.reduce(%{}, fn conn, acc ->
        Map.put(acc, conn.id, :unknown)
      end)

    socket = socket |> assign(:power_states, power_states)

    connection_states =
      connections
      |> Enum.reduce(%{}, fn conn, acc ->
        state =
          case RadioConnection.process_exists?(conn) do
            true ->
              RadioConnection.query_power_state(conn)
              :up

            false ->
              :stopped
          end

        Map.put(acc, conn.id, state)
      end)

    socket =
      socket
      |> assign_theme()
      |> assign(:connections, connections)
      |> assign(:connection_states, connection_states)
      |> assign(:status_message, nil)

    if connected?(socket) do
      for c <- connections do
        Logger.info("Subscribing to connection:#{c.id}")
        Phoenix.PubSub.subscribe(Open890.PubSub, "connection:#{c.id}")
      end
    end

    {:ok, socket}
  end

  def handle_event(event, %{"id" => _id, "key" => key} = params, socket)
      when event in [
             "wake",
             "start_connection",
             "stop_connection",
             "power_off",
             "delete_connection"
           ] do
    if activation_key?(key) do
      handle_event(event, Map.delete(params, "key"), socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "start_connection" = event,
        %{"id" => id} = params,
        %{assigns: assigns} = socket
      ) do
    Logger.debug("**** ConnectionsLive: handle_event: #{event}, params: #{inspect(params)}")

    result = RadioConnection.start(id)
    conn_name = connection_name(assigns, id)

    socket =
      case result do
        {:ok, _conn} ->
          new_connection_states = assigns.connection_states |> Map.put(id, :starting)
          Process.send_after(self(), {:verify_connection_start, id}, 2_500)

          socket
          |> assign(:connection_states, new_connection_states)
          |> put_status("#{conn_name}: start requested.")

        {:error, reason} ->
          Logger.warn("Could not start connection #{id}: #{inspect(reason)}")
          socket |> put_status("#{conn_name}: unable to start (#{format_reason(reason)}).")

        _ ->
          Logger.warn("Could not start connection: #{inspect(result)}")
          socket |> put_status("#{conn_name}: unable to start.")
      end

    {:noreply, socket}
  end

  def handle_event(
        "stop_connection" = event,
        %{"id" => id} = params,
        %{assigns: assigns} = socket
      ) do
    Logger.debug("ConnectionsLive: handle_event: #{event}, params: #{inspect(params)}")

    conn_name = connection_name(assigns, id)
    result = id |> RadioConnection.stop()

    socket =
      case result do
        :ok ->
          Logger.info("stopped connection id #{id}")
          new_connection_states = assigns.connection_states |> Map.put(id, :stopped)
          new_power_states = assigns.power_states |> Map.put(id, :unknown)

          socket
          |> assign(:connection_states, new_connection_states)
          |> assign(:power_states, new_power_states)
          |> put_status("#{conn_name}: stopped.")

        {:error, reason} ->
          Logger.warn("Unable to stop connection #{id}: #{inspect(reason)}")
          socket |> put_status("#{conn_name}: unable to stop (#{format_reason(reason)}).")
      end

    {:noreply, socket}
  end

  def handle_event(
        "delete_connection" = _event,
        %{"id" => id} = _params,
        %{assigns: assigns} = socket
      ) do
    status_message =
      case RadioConnection.find(id) do
        {:ok, connection} ->
          RadioConnection.stop(id)
          RadioConnection.delete_connection(connection)
          "#{connection.name}: deleted."

        _ ->
          Logger.warn("Could not find connection id: #{inspect(id)}")
          "Connection #{id}: not found."
      end

    new_connections =
      assigns.connections
      |> Enum.reject(fn x -> x.id == id end)

    socket =
      socket
      |> assign(%{
        connections: new_connections,
        power_states: Map.delete(assigns.power_states, id),
        connection_states: Map.delete(assigns.connection_states, id),
        status_message: status_message
      })

    {:noreply, socket}
  end

  def handle_event("power_off" = _event, %{"id" => id} = _params, %{assigns: assigns} = socket) do
    conn_name = connection_name(assigns, id)

    socket =
      case RadioConnection.find(id) do
        {:ok, conn} ->
          case RadioConnection.power_off(conn) do
            :ok ->
              socket |> put_status("#{conn_name}: power off requested.")

            {:error, reason} ->
              socket |> put_status("#{conn_name}: power off failed (#{format_reason(reason)}).")

            other ->
              socket |> put_status("#{conn_name}: power off result #{inspect(other)}.")
          end

        _ ->
          Logger.warn("Could not find connection: #{inspect(id)}")
          socket |> put_status("Connection #{id}: not found.")
      end

    {:noreply, socket}
  end

  def handle_event("wake" = _event, %{"id" => id} = _params, %{assigns: assigns} = socket) do
    conn_name = connection_name(assigns, id)

    socket =
      case RadioConnection.find(id) do
        {:ok, conn} ->
          case RadioConnection.wake(conn) do
            :ok ->
              socket |> put_status("#{conn_name}: wake requested.")

            {:error, reason} ->
              socket |> put_status("#{conn_name}: wake failed (#{format_reason(reason)}).")

            other ->
              socket |> put_status("#{conn_name}: wake result #{inspect(other)}.")
          end

        _ ->
          Logger.warn("Could not find connection: #{inspect(id)}")
          socket |> put_status("Connection #{id}: not found.")
      end

    {:noreply, socket}
  end

  def handle_event(event, params, %{assigns: _assigns} = socket) do
    Logger.debug("ConnectionsLive: default handle_event: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_info({:verify_connection_start, connection_id}, %{assigns: assigns} = socket) do
    case Map.get(assigns.connection_states, connection_id) do
      :starting ->
        case RadioConnection.find(connection_id) do
          {:ok, conn} ->
            conn_name = connection_name(assigns, connection_id)

            if RadioConnection.process_exists?(conn) do
              new_connection_states = assigns.connection_states |> Map.put(connection_id, :up)

              socket =
                socket
                |> assign(:connection_states, new_connection_states)
                |> put_status("#{conn_name}: connection is up.")

              {:noreply, socket}
            else
              new_connection_states =
                assigns.connection_states |> Map.put(connection_id, :stopped)

              socket =
                socket
                |> assign(:connection_states, new_connection_states)
                |> put_status("#{conn_name}: start failed (radio busy or credentials issue).")

              {:noreply, socket}
            end

          _ ->
            {:noreply, socket |> put_status("Connection #{connection_id}: not found.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "connection_state", payload: payload}, socket) do
    new_connection_states =
      socket.assigns.connection_states
      |> Map.put(payload.id, payload.state)

    conn_name = connection_name(socket.assigns, payload.id)
    state_label = payload.state |> pretty_connection_state() |> to_string()

    socket =
      socket
      |> assign(:connection_states, new_connection_states)
      |> put_status("#{conn_name}: connection #{state_label}.")

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{
          event: "power_state",
          payload: %{id: connection_id, state: power_state} = _payload
        },
        socket
      ) do
    new_power_states = socket.assigns.power_states |> Map.put(connection_id, power_state)

    conn_name = connection_name(socket.assigns, connection_id)

    socket =
      socket
      |> assign(:power_states, new_power_states)
      |> put_status("#{conn_name}: power #{power_state}.")

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    Logger.debug(
      "ConnectionsLive: unhandled broadcast event: #{event}, payload: #{inspect(payload)}"
    )

    {:noreply, socket}
  end

  defp assign_theme(conn) do
    conn |> assign(:bg_theme, "light")
  end

  defp pretty_connection_state({type, _extra}) do
    type
  end

  defp pretty_connection_state(state) when is_atom(state) do
    state
  end

  defp pretty_connection_state(other) do
    Logger.warn("*** Unknown connection state: #{inspect(other)}")
    :unknown_other
  end

  defp connection_up?(:up), do: true
  defp connection_up?(_), do: false

  defp power_on?(:on), do: true
  defp power_on?(_), do: false

  defp put_status(socket, message) do
    socket |> assign(:status_message, message)
  end

  defp activation_key?(key) when is_binary(key) do
    key in ["Enter", "NumpadEnter", " ", "Space", "Spacebar"]
  end

  defp activation_key?(_), do: false

  defp connection_name(assigns, id) do
    case assigns.connections |> Enum.find(fn conn -> conn.id == id end) do
      nil -> "Connection #{id}"
      conn -> conn.name
    end
  end

  defp replace_connection(connections, updated_connection) do
    connections
    |> Enum.map(fn conn ->
      if conn.id == updated_connection.id, do: updated_connection, else: conn
    end)
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
