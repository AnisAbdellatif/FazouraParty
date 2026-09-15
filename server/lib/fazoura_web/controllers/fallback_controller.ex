defmodule FazouraWeb.FallbackController do
  @moduledoc "Maps context errors to JSON API responses (QUIZ_FORMAT.md §5)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [error: 4, error: 5]

  def call(conn, {:error, :quiz_not_found}),
    do:
      error(
        conn,
        :not_found,
        "quiz_not_found",
        "That quiz doesn't exist or isn't shared with you."
      )

  def call(conn, {:error, :owner_key_required}),
    do:
      error(
        conn,
        :unauthorized,
        "owner_key_required",
        "Send this device's owner key in the x-owner-key header."
      )

  def call(conn, {:error, :invalid_scope}),
    do: error(conn, :unprocessable_entity, "invalid_scope", "scope must be public or mine.")

  def call(conn, {:error, :unknown_image}),
    do:
      error(
        conn,
        :unprocessable_entity,
        "unknown_image",
        "A photo question uses an image that wasn't uploaded from this device."
      )

  def call(conn, {:error, :image_too_large}),
    do:
      error(conn, :request_entity_too_large, "image_too_large", "Images must be 2 MB or smaller.")

  def call(conn, {:error, :unsupported_image}),
    do:
      error(conn, :unsupported_media_type, "unsupported_image", "Use a JPEG, PNG or WebP image.")

  def call(conn, {:error, :empty_pack}),
    do: error(conn, :unprocessable_entity, "empty_pack", "That quiz has no questions.")

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    error(conn, :unprocessable_entity, "invalid_quiz", "The quiz has errors.", %{
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    })
  end

  defp translate_error({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
