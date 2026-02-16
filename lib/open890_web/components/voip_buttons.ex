defmodule Open890Web.Components.VoipButtons do
  use Phoenix.Component

  attr :enabled, :boolean, required: true

  def mic_button(assigns) do
    ~H"""
      <%= if @enabled do %>
        <button type="button" class="ui small green button" phx-click="toggle_mic" aria-pressed="true">
          <i class="icon microphone"></i> VOIP Mic: ON
        </button>
      <% else %>
        <button type="button" class="ui small red inverted button" phx-click="toggle_mic" aria-pressed="false">
          <i class="icon microphone slash"></i> VOIP Mic: OFF
        </button>
      <% end %>
    """
  end
end
