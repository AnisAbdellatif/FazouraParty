# Loads the built-in quizzes from priv/quizzes/*.json into the database.
# Idempotent: run by `mix ecto.setup` / `mix setup`, safe to re-run after editing them.
quizzes = Fazoura.Quizzes.sync_builtin!()
IO.puts("Synced #{length(quizzes)} built-in quiz(zes)")
