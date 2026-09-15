defmodule Fazoura.Settings.Setting do
  @moduledoc "One editable server setting, stored as JSON text (see `Fazoura.Settings`)."

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}

  schema "app_settings" do
    field :value, :string

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}
end
