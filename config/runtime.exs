import Config
require Logger

if config_env() in [:dev, :prod] do
  # just always make a new secret_key_base
  secret_key_base = :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)

  host = System.get_env("OPEN890_HOST", "localhost")
  port = System.get_env("OPEN890_PORT", "4000") |> String.to_integer()

  config :open890, Open890Web.Endpoint,
    http: [
      port: port,
      transport_options: [socket_opts: [:inet6]]
    ],
    check_origin: false,
    url: [host: host, port: port],
    server: true,
    secret_key_base: secret_key_base

  udp_port = System.get_env("OPEN890_UDP_PORT", "60001") |> String.to_integer()
  udp_port = Enum.min([udp_port, 65_535])

  config :open890, Open890.UDPAudioServer, port: udp_port

  tx_mic_gain =
    case Float.parse(System.get_env("OPEN890_TX_MIC_GAIN", "1.0")) do
      {parsed, _} -> parsed
      :error -> 1.0
    end
    |> max(0.01)
    |> min(8.0)

  config :open890, Open890.TCPClient, tx_mic_gain: tx_mic_gain

  rnnoise_enabled =
    case System.get_env("OPEN890_RNNOISE_ENABLED", "false") |> String.downcase() do
      "1" -> true
      "true" -> true
      "yes" -> true
      "on" -> true
      _ -> false
    end

  rnnoise_timeout_ms =
    System.get_env("OPEN890_RNNOISE_TIMEOUT_MS", "30")
    |> String.to_integer()
    |> max(5)
    |> min(1000)

  priv_dir =
    case :code.priv_dir(:open890) do
      dir when is_list(dir) -> to_string(dir)
      _ -> Path.expand("../priv", __DIR__)
    end

  pick_default_executable = fn candidates ->
    Enum.find(candidates, &File.exists?/1) || hd(candidates)
  end

  rnnoise_executable =
    System.get_env(
      "OPEN890_RNNOISE_BIN",
      pick_default_executable.([
        Path.join(priv_dir, "bin/open890_rnnoise_filter"),
        Path.join(priv_dir, "bin/open890_rnnoise_filter_static"),
        Path.expand("../priv/bin/open890_rnnoise_filter", __DIR__),
        Path.expand("../priv/bin/open890_rnnoise_filter_static", __DIR__)
      ])
    )

  config :open890, Open890.RNNoisePort,
    enabled: rnnoise_enabled,
    executable: rnnoise_executable,
    timeout_ms: rnnoise_timeout_ms

  ft8_enabled =
    case System.get_env("OPEN890_FT8_ENABLED", "false") |> String.downcase() do
      "1" -> true
      "true" -> true
      "yes" -> true
      "on" -> true
      _ -> false
    end

  ft8_timeout_ms =
    System.get_env("OPEN890_FT8_TIMEOUT_MS", "1200")
    |> String.to_integer()
    |> max(100)
    |> min(10_000)

  ft8_sample_rate_hz =
    System.get_env("OPEN890_FT8_SAMPLE_RATE_HZ", "16000")
    |> String.to_integer()
    |> max(8000)
    |> min(48_000)

  ft8_window_seconds =
    System.get_env("OPEN890_FT8_WINDOW_SECONDS", "15")
    |> String.to_integer()
    |> max(5)
    |> min(30)

  ft8_executable =
    System.get_env(
      "OPEN890_FT8_BIN",
      pick_default_executable.([
        Path.join(priv_dir, "bin/open890_ft8_decoder"),
        Path.expand("../priv/bin/open890_ft8_decoder", __DIR__)
      ])
    )

  config :open890, Open890.FT8DecoderPort,
    enabled: ft8_enabled,
    executable: ft8_executable,
    timeout_ms: ft8_timeout_ms,
    sample_rate_hz: ft8_sample_rate_hz,
    window_seconds: ft8_window_seconds

  Logger.info(
    "Configured OPEN890_HOST: #{inspect(host)}, OPEN890_PORT: #{inspect(port)}, OPEN890_UDP_PORT: #{inspect(udp_port)}, OPEN890_TX_MIC_GAIN: #{inspect(tx_mic_gain)}, OPEN890_RNNOISE_ENABLED: #{inspect(rnnoise_enabled)}, OPEN890_FT8_ENABLED: #{inspect(ft8_enabled)}"
  )

  release_db_default =
    if System.get_env("RELEASE_NAME") not in [nil, ""] do
      home_dir = System.user_home() || System.get_env("HOME") || "."

      Path.join([
        home_dir,
        "Library",
        "Application Support",
        "open890",
        "db",
        "radio_connections.dets"
      ])
    else
      "db/radio_connections.dets"
    end

  radio_connections_db_path =
    case {System.get_env("OPEN890_DB_PATH"), System.get_env("OPEN890_DB_DIR")} do
      {path, _} when is_binary(path) and path != "" ->
        path

      {_, dir} when is_binary(dir) and dir != "" ->
        Path.join(dir, "radio_connections.dets")

      _ ->
        release_db_default
    end

  config :open890, Open890.RadioConnectionRepo,
    database: :open890,
    database_file: radio_connections_db_path
else
  config :open890, Open890.UDPAudioServer, port: 60001
  config :open890, Open890.TCPClient, tx_mic_gain: 1.0
  config :open890, Open890.RNNoisePort, enabled: false, timeout_ms: 30

  config :open890, Open890.FT8DecoderPort,
    enabled: false,
    timeout_ms: 1200,
    sample_rate_hz: 16_000,
    window_seconds: 15

  config :open890, Open890.RadioConnectionRepo,
    database: :open890_test,
    database_file: "db/radio_connections_test.dets"
end
