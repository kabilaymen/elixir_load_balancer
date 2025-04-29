defmodule ElixirLoadBalancerTest do
  use ExUnit.Case
  doctest ElixirLoadBalancer

  test "greets the world" do
    assert ElixirLoadBalancer.hello() == :world
  end
end
