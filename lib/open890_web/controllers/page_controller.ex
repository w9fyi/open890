defmodule Open890Web.PageController do
  use Open890Web, :controller

  alias Open890.RadioConnection

  def index(conn, _params) do
    destination =
      case RadioConnection.all() do
        [%RadioConnection{id: id, auto_launch: auto_launch}]
        when auto_launch in [true, "true"] ->
          "/connections/#{id}"

        _ ->
          "/connections"
      end

    conn
    |> redirect(to: destination)
    |> halt()
  end
end
