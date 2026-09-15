defmodule Fazoura.Quizzes.Image do
  @moduledoc "An uploaded question photo; the file lives in the uploads directory."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "images" do
    field :key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :owner_key_hash, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
