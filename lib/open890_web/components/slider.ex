defmodule Open890Web.Components.Slider do
  use Phoenix.Component

  attr :click, :string, required: false
  attr :aria_label, :string, required: false
  attr :enabled, :boolean, default: true
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :min_value, :integer, required: false
  attr :max_value, :integer, required: false
  attr :padded_top_value, :integer, required: false
  attr :padded_top, :boolean, default: false
  attr :step, :integer, required: false
  attr :value, :any, required: true
  attr :wheel, :string, required: false, default: nil

  def slider(assigns) do
    labeled = !is_nil(assigns[:label]) && assigns[:label] != ""
    min_value = Map.get(assigns, :min_value, 0)
    max_value = Map.get(assigns, :max_value, 255)
    step = Map.get(assigns, :step, 1)
    value = normalized_value(assigns[:value])
    computed_aria_label =
      case Map.get(assigns, :aria_label) do
        label when is_binary(label) and label != "" -> label
        _ -> aria_label(assigns[:label], assigns[:id])
      end

    assigns = assign(assigns, %{
      labeled: labeled,
      min_value: min_value,
      max_value: max_value,
      step: step,
      value: value,
      aria_label: computed_aria_label
    })

    ~H"""
      <div class={component_classes(assigns)}>
        <%= if @labeled do %>
          <span class="label"><%= @label %></span>
        <% end %>
        <div
          class={wrapper_class(assigns)}
          phx-hook="Slider"
          data-click-action={@click}
          data-wheel-action={@wheel}
          data-enabled={enabled_state(assigns)}
          data-min-value={@min_value}
          data-max-value={@max_value}
          data-current-value={@value}
          data-step={@step}
          id={@id || id_for(@label)}>
          <input
            class="sliderRangeInput"
            type="range"
            min={@min_value}
            max={@max_value}
            step={@step}
            value={@value}
            disabled={!@enabled}
            aria-label={@aria_label}
            aria-valuemin={@min_value}
            aria-valuemax={@max_value}
            aria-valuenow={@value}
            aria-valuetext={slider_value_text(@aria_label, @value)} />
          <div class="indicator" style={style_attr(@value, @max_value)}></div>
        </div>
      </div>
    """
  end

  def normalized_value(value) when is_integer(value), do: value
  def normalized_value(_), do: 0

  def aria_label(label, _id) when is_binary(label) and label != "" do
    "#{label} slider"
  end

  def aria_label(_, id) when is_binary(id), do: "#{id} slider"
  def aria_label(_, _), do: "slider"

  def slider_value_text(label, value) do
    "#{label}: #{value}"
  end

  def enabled_state(assigns) do
    assigns
    |> Map.get(:enabled, true)
    |> to_string()
  end

  def style_attr(value, max_value) when is_integer(value) and is_integer(max_value) and max_value > 0 do
    width = value / 1
    percentage = width / max_value
    width = (percentage * 255) |> round()

    "width: #{width}px;"
  end

  def style_attr(_, _), do: "width: 0px;"

  def id_for(label) do
    "#{label}Slider"
  end

  def component_classes(assigns) do
    top_padded = assigns |> Map.get(:padded_top, false)

    component_classes = ["slider"]

    component_classes =
      if top_padded do
        component_classes ++ ["padded-top"]
      else
        component_classes
      end

    Enum.join(component_classes, " ")
  end

  def wrapper_class(assigns) do
    label = assigns.label
    enabled = assigns |> Map.get(:enabled, true)
    wrapper_classes = ["sliderWrapper"]

    wrapper_classes =
      if !is_nil(label) && label != "" do
        wrapper_classes ++ ["labeled"]
      else
        wrapper_classes
      end

    wrapper_classes =
      if enabled do
        wrapper_classes ++ ["enabled"]
      else
        wrapper_classes ++ ["disabled"]
      end

    Enum.join(wrapper_classes, " ")
  end
end
