defmodule Open890Web.Components.VoipButtons do
  use Phoenix.Component

  attr :enabled, :boolean, required: true

  def mic_button(assigns) do
    ~H"""
    <%= if @enabled do %>
      <button
        type="button"
        class="ui small green button"
        phx-click="toggle_mic"
        aria-pressed="true"
        aria-label="VOIP microphone on. Activate to turn off."
      >
        <i class="icon microphone" aria-hidden="true"></i>
        <span role="status" aria-live="polite">VOIP Mic: ON</span>
      </button>
    <% else %>
      <button
        type="button"
        class="ui small red inverted button"
        phx-click="toggle_mic"
        aria-pressed="false"
        aria-label="VOIP microphone off. Activate to turn on."
      >
        <i class="icon microphone slash" aria-hidden="true"></i>
        <span role="status" aria-live="polite">VOIP Mic: OFF</span>
      </button>
    <% end %>
    """
  end
end
