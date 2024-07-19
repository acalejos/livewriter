# Livewriter

Tools for programmatically writing Elixir Livebook notebooks using Elixir.

For now, `Livewriter` exposes a small and simple Domain Specific Language (DSL) for Livebooks,
as well as a `from_docs` macro to generate Livebooks from the given modules' documentation.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `livewriter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:livewriter, github: "acalejos/livewriter"}
  ]
end
```

## Configuration

You will need to configure your application to use the `:livebook` dependency included in
`Livewriter`. Here is an example of a minimal configuration you can use:

### `config.exs`

```elixir
import Config

config :livebook,
  aws_credentials: false,
  epmdless: true,
  iframe_port: 8082,
  default_runtime: {Livebook.Runtime.Embedded, []}

config :livebook, Livebook.Apps.Manager, retry_backoff_base_ms: 500
```

### `runtime.exs`

```elixir
Livebook.config_runtime()
```

## Examples

```elixir
import Livewriter

livebook do
  setup do
    Mix.install([
      {:ecto, "~> 3.11"}
    ])
  end
  
  section id: "section1" do
    elixir do
      a = 1
      b = 2
      c = a + b
    end

    elixir do
      d = c * b * a
    end
  end

  section name: "Forked", fork: "section1" do
    elixir do
      IO.puts("First Line")
    end

    markdown do
      """
      This is some markdown:

      * You can see clearly now
      """
    end
  end
end
|> print!()
```

```elixir
import Livewriter
result = Livewriter.from_docs(Test) |> print!(include_outputs: true)
```
