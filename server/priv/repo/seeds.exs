# Loads the quizzes that ship with or are dropped into the server:
# `priv/quizzes/*.json` and every `.fazoura` package in the packages directory.
# Idempotent: run by `mix ecto.setup` / `mix setup`, safe to re-run after editing them.
quizzes = Fazoura.Quizzes.sync_builtin!()
packages = Fazoura.Quizzes.sync_packages!()

IO.puts("Synced #{length(quizzes)} built-in quiz(zes) and #{length(packages)} package(s)")
