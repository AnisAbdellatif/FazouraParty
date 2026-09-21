# Quiz packages (development)

Drop `.fazoura` files here and `mix setup` loads them into your local database
(protocol/QUIZ_FORMAT.md §6). This is the default `:packages_dir`; **in production the
directory is `PACKAGES_DIR`**, which `deploy/Dockerfile` sets to `/data/packages` and
`deploy/compose.yaml` bind-mounts from `./packages` beside it — so packages are copied
onto the server rather than baked into the image, and nothing here is read there.

- **The filename is the slug.** `film-night.fazoura` becomes a preset hostable as
  `{"quiz_id": "film-night"}`, and re-running updates that quiz rather than adding a
  second one.
- **A package carries its photos**, so unlike `priv/quizzes/*.json` there is nothing to
  publish first — they are stored as ordinary uploads on the way in.
- **A package that cannot be read stops the sync**, because this also runs on a deploy,
  and a quiz someone put there going quietly missing is worse than a failed release.

Build one from a folder of JSON and images with `tools/fazoura_pack.py`, or download one
from the admin dashboard.
