defmodule Fazoura.ProtocolFixtures do
  @moduledoc "Loads the shared contract fixtures from `<repo>/protocol/fixtures`."

  @dir Path.expand("../../../protocol/fixtures", __DIR__)

  def dir, do: @dir

  def load!(relative), do: @dir |> Path.join(relative) |> File.read!() |> Jason.decode!()
end
