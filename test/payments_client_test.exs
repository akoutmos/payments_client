defmodule PaymentsClientTest do
  use ExUnit.Case
  doctest PaymentsClient

  test "greets the world" do
    assert PaymentsClient.hello() == :world
  end
end
