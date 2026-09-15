defmodule FazouraWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import FazouraWeb.ChannelCase

      @endpoint FazouraWeb.Endpoint
    end
  end
end
