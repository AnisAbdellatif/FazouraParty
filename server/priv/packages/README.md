# Quiz packages

`.fazoura` files here ship with the server and are seeded into the database on every
setup — `mix setup` locally, `Fazoura.Release.setup/0` on every deploy
(protocol/QUIZ_FORMAT.md §6). They are committed, so they travel in the image the same
way `priv/quizzes/*.json` does.

- **The filename is the slug.** `film-night.fazoura` becomes a preset hostable as
  `{"quiz_id": "film-night"}`, and changing the file updates that quiz rather than adding
  a second one.
- **A package carries its photos**, so unlike a JSON quiz there is nothing to publish
  first — they are stored as ordinary uploads on the way in.
- **A package that cannot be read stops the sync**, because this runs on a deploy, and a
  quiz going quietly missing is worse than a release that stops.

`PACKAGES_DIR` names a **second** directory, read after this one — a drop folder on the
server, so a quiz can be added or corrected without rebuilding the image. A package there
with the same slug as one here wins, which is what makes it a correction.

Build one from a folder of JSON and images with `tools/fazoura-cli/fazoura quiz pack`, or download one
from the admin dashboard.

Keep an eye on size: everything here is in the image and in git history for good. A large
quiz is often better dropped on the server than committed.
