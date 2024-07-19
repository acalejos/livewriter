defmodule LivewriterTest do
  use ExUnit.Case
  doctest Livewriter

  test "greets the world" do
    assert Livewriter.hello() == :world
  end
end
