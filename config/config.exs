import Config

config :livebook,
  aws_credentials: false,
  epmdless: true,
  iframe_port: 8082,
  default_runtime: {Livebook.Runtime.Embedded, []}

config :livebook, Livebook.Apps.Manager, retry_backoff_base_ms: 500
