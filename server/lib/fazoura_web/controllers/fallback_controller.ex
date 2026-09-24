defmodule FazouraWeb.FallbackController do
  @moduledoc "Maps context errors to JSON API responses (QUIZ_FORMAT.md §5)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [error: 4, error: 5]

  alias Fazoura.Quizzes.{Report, Review}

  # A submission that is not this device's, or is gone (QUIZ_FORMAT.md §4).
  def call(conn, {:error, :not_found}),
    do: error(conn, :not_found, "not_found", "That does not exist.")

  def call(conn, {:error, :invalid_quiz}),
    do:
      error(
        conn,
        :unprocessable_entity,
        "invalid_quiz",
        "That package is not a quiz with a title and at least one question."
      )

  # A package that cannot be read, each by its own code (QUIZ_FORMAT.md §5.4). These
  # used to have no clause here, so a file that was not a ZIP answered 500.
  def call(conn, {:error, reason})
      when reason in [:archive_too_large, :invalid_archive, :manifest_missing, :manifest_invalid],
      do:
        error(
          conn,
          :unprocessable_entity,
          Atom.to_string(reason),
          if(reason == :archive_too_large,
            do: "That package is too large, or unpacks into far more than a quiz needs.",
            else: "That file isn't a readable .fazoura package."
          )
        )

  def call(conn, {:error, :too_many_submissions}),
    do:
      error(
        conn,
        :too_many_requests,
        "too_many_submissions",
        "You already have #{Review.max_pending_per_owner()} quizzes " <>
          "waiting for review. Try again once some have been read."
      )

  def call(conn, {:error, :review_queue_full}),
    do:
      error(
        conn,
        :service_unavailable,
        "review_queue_full",
        "The review queue is full right now. Try again later."
      )

  def call(conn, {:error, :quiz_in_play}),
    do:
      error(
        conn,
        :conflict,
        "quiz_in_play",
        "A public room is playing this quiz right now. Try again once its game is over."
      )

  def call(conn, {:error, :quiz_not_found}),
    do:
      error(
        conn,
        :not_found,
        "quiz_not_found",
        "That quiz doesn't exist or was unpublished."
      )

  def call(conn, {:error, :owner_key_required}),
    do:
      error(
        conn,
        :unauthorized,
        "owner_key_required",
        "Send this device's publisher key in the x-owner-key header."
      )

  def call(conn, {:error, :invalid_report}),
    do:
      error(
        conn,
        :unprocessable_entity,
        "invalid_report",
        "Pick one of: #{Enum.join(Report.reasons(), ", ")}."
      )

  # Reporting a question from a room that came from a private quiz: nothing was
  # published, so there is nothing anybody could take down (QUIZ_FORMAT.md §5.9).
  def call(conn, {:error, :quiz_not_public}),
    do:
      error(
        conn,
        :unprocessable_entity,
        "quiz_not_public",
        "That quiz isn't published — the host made it on their own device, so there is nothing for us to remove."
      )

  def call(conn, {:error, :question_not_found}),
    do:
      error(
        conn,
        :not_found,
        "question_not_found",
        "That question isn't in this room."
      )

  def call(conn, {:error, :unknown_player}),
    do: error(conn, :not_found, "unknown_player", "That player isn't in this room.")

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

  def call(conn, {:error, :quiz_too_large}),
    do:
      error(
        conn,
        :request_entity_too_large,
        "quiz_too_large",
        "That quiz's photos are too large to host: #{div(Fazoura.Quizzes.max_inline_bytes(), 1024 * 1024)} MB in total at most."
      )

  def call(conn, {:error, :too_many_rooms}),
    do:
      error(
        conn,
        :service_unavailable,
        "too_many_rooms",
        "Too many games are running right now. Try again in a few minutes."
      )

  def call(conn, {:error, :rate_limited}),
    do:
      error(
        conn,
        :too_many_requests,
        "rate_limited",
        "Too many requests from this device. Wait a moment and try again."
      )

  def call(conn, {:error, :unsupported_image}),
    do:
      error(conn, :unsupported_media_type, "unsupported_image", "Use a JPEG, PNG or WebP image.")

  def call(conn, {:error, :image_not_found}),
    do:
      error(
        conn,
        :not_found,
        "image_not_found",
        "A photo of that quiz is no longer available, so it can't be packaged for offline play."
      )

  def call(conn, {:error, :empty_pack}),
    do: error(conn, :unprocessable_entity, "empty_pack", "That quiz has no questions.")

  # Also the answer when the host token was wrong: a caller who cannot open the
  # room is not told one exists (PROTOCOL.md §3.1).
  def call(conn, {:error, :room_not_found}),
    do: error(conn, :not_found, "room_not_found", "That room does not exist or has ended.")

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
