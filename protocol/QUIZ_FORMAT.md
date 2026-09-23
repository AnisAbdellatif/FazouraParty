# Fazoura Party — Quiz format, storage and API

**Quiz format version: `1`** · Companion to [PROTOCOL.md](PROTOCOL.md) (which covers live rooms).

Writing one by hand? [QUIZ_AUTHORING.md](QUIZ_AUTHORING.md) is the how-to: the folder to
build, where the photos go, and how to pack it.

A *quiz* (called a *pack* in older parts of the room protocol) is the content a room plays:
a titled, ordered list of questions. Quizzes are **JSON documents** at every boundary —
built-in quiz files in the repo, the REST API, import/export — and are stored in a
relational database through Ecto (SQLite on developer machines, Postgres on the server).

---

## 1. Design goals

1. **One canonical JSON document** for a quiz. Built-in files, API bodies and exports all
   use it, so a quiz can move between them unchanged.
2. **Evolvable.** Every document carries `format_version`. New optional fields can be
   added without a version bump; readers ignore unknown keys. Removing or re-meaning a
   field, or adding a required one, bumps `format_version` and needs a migration path.
3. **Room-safe.** Rooms snapshot a quiz when created (PROTOCOL.md §6.2), so editing a quiz
   never affects a running game.
4. **No accidental answer leaks.** Accepted answers are omitted from public listings and
   ordinary quiz reads. A user who explicitly saves a public quiz for offline play opts in
   to receiving its full document, including accepted answers, so the device can host it
   without the server.
5. **No accounts.** A quiz is either *private* (kept on the device that made it and sent
   to the server only for the lifetime of a room) or *public* (published to the server
   database for everyone). A per-device secret lets the publishing device update or
   unpublish; the model leaves room for a user id later without changing the document.

## 2. Quiz document (format version 1)

```json
{
  "format_version": 1,
  "version": "1.0",
  "id": "3f0c2a5e-6b1e-4f0a-9d8e-2b7c1e4a9f10",
  "slug": null,
  "title": "Movie Night",
  "description": "Blockbusters from the last 30 years.",
  "language": "en",
  "tags": ["movies", "cinema", "2000s"],
  "source": "custom",
  "visibility": "public",
  "is_owner": true,
  "default_settings": {
    "time_limit_ms": 30000,
    "difficulty_multiplier": false
  },
  "question_count": 2,
  "has_photos": true,
  "created_at": "2026-09-16T10:00:00Z",
  "updated_at": "2026-09-16T10:05:00Z",
  "questions": [
    {
      "id": "8a1d…",
      "type": "text",
      "prompt": "Who directed Jurassic Park?",
      "accepted_answers": ["Steven Spielberg", "Spielberg"],
      "difficulty": "easy",
      "time_limit_ms": null,
      "image": null,
      "explanation": null
    },
    {
      "id": "c47e…",
      "type": "text_photo",
      "prompt": "Which film is this still from?",
      "accepted_answers": ["The Matrix"],
      "difficulty": "medium",
      "time_limit_ms": null,
      "image": {
        "key": "5b0e4f1c9a2d7e3f.jpg",
        "url": "https://party.example.com/uploads/5b0e4f1c9a2d7e3f.jpg",
        "alt": "A man in a long black coat dodging bullets"
      },
      "explanation": "The bullet-time scene, 1999."
    }
  ]
}
```

### 2.1 Quiz fields

| Field | Type | Rules |
|---|---|---|
| `format_version` | int | Required on input; currently `1` |
| `version` | string | Content revision in `<major>.<minor>` format, starting at `"1.0"`; the minor version increments whenever a published quiz is replaced. Clients use it to detect stale offline copies |
| `id` | uuid string | Server-assigned; ignored on create |
| `slug` | string \| null | Stable human id for built-in quizzes (`general-knowledge`); `null` for custom |
| `title` | string | Required, 1–80 characters (trimmed) |
| `description` | string \| null | ≤ 280 characters |
| `language` | string | BCP-47-ish code, 2–10 chars, default `"en"`. Metadata, not layout: a client works out which way a line reads from the line itself (first strong character, UAX #9), because a quiz may mix scripts and a player answers in whichever they like |
| `tags` | string[] | Required: 1–10 tags in display order, each 1–24 characters. Free text, normalised to lower case with collapsed whitespace and de-duplicated (§2.3) |
| `source` | `"builtin"` \| `"custom"` | Server-assigned |
| `visibility` | `"public"` \| `"private"` | Stored quizzes are always `public`; the app uses `private` for quizzes kept on the device (§4). Ignored on input |
| `is_owner` | bool | Output only: whether the request's publisher key published this quiz |
| `default_settings` | object | Suggested room settings. `time_limit_ms` 10 000–120 000 (default 30 000), `difficulty_multiplier` bool (default false). Rooms start with these; the host can still change them in the lobby |
| `question_count` | int | Output only |
| `has_photos` | bool | Output only: at least one `text_photo` question |
| `created_at`, `updated_at` | ISO 8601 UTC | Output only |
| `questions` | Question[] | Required on create/replace: 1–1024 questions, in play order |

### 2.2 Question fields

| Field | Type | Rules |
|---|---|---|
| `id` | uuid string | Server-assigned; stable across edits only while the quiz exists |
| `type` | `"text"` \| `"text_photo"` | Required. Future types (e.g. `multiple_choice`) will add fields; readers must skip question types they don't know |
| `prompt` | string | Required, 1–280 characters |
| `accepted_answers` | string[] | Required, 1–10 answers, each 1–100 characters. Matching is PROTOCOL.md §8 |
| `difficulty` | `"easy"` \| `"medium"` \| `"hard"` | Default `"easy"`; drives the difficulty bonus (PROTOCOL.md §9) |
| `time_limit_ms` | int \| null | Reserved for per-question overrides; ignored by rooms today |
| `image` | object \| null | Required for `text_photo`, must be `null` for `text`. Fields: `key` (an upload, §5.7 — what a published quiz carries); `data` (base64 JPEG/PNG/WebP ≤ 2 MB, for private quizzes sent inline, §5.8, and how the app keeps photos on the device); `path` (a file beside the document — inside a `.fazoura` package, §5.3b, which is how a photo reaches the server when publishing, or beside a preset's JSON, §6); optional `alt` (≤ 140 chars); `url` is output only |
| `explanation` | string \| null | ≤ 280 chars, shown after the reveal in a later release |

### 2.3 Tags

Tags replace the old fixed category: a quiz carries **one to ten** of them, and any text
is allowed, so people can group quizzes however they like ("pub quiz", "office party",
"شعر").

- Normalised by the server: lower-cased, outer whitespace trimmed, inner whitespace
  collapsed, duplicates dropped, order preserved. So `"Pop  Culture"` and `"pop culture"`
  are the same tag.
- 1–24 characters each; a quiz needs at least one tag and at most ten.
- Clients offer **suggested tags** as quick picks. They are a convenience, not a closed
  list. The server serves them from `GET /api/tags` and an admin edits them (ADMIN.md
  §3.3); apps keep this built-in list as the offline fallback:

  `general`, `science`, `history`, `geography`, `movies`, `tv`, `music`, `sports`,
  `food`, `nature`, `technology`, `art`, `books`, `gaming`, `pop culture`, `language`

- The first tag also picks a quiz card's colour in the app; unknown tags get a stable
  colour derived from the tag itself.

## 3. Storage (Ecto)

Portable across SQLite and Postgres: no Postgres-only SQL, string enums (validated in
changesets), arrays via Ecto's `{:array, :string}`.

```
quizzes
  id uuid PK · slug string UNIQUE NULL · format_version int · version string
  title string · description text NULL · language string
  source string · visibility string · owner_key_hash string NULL (sha256 hex)
  default_time_limit_ms int · default_difficulty_multiplier bool
  question_count int · has_photos bool (denormalised for listing)
  inserted_at · updated_at
  INDEX (visibility, updated_at) · INDEX (owner_key_hash)

quiz_tags
  id uuid PK · quiz_id FK → quizzes ON DELETE CASCADE · tag string · position int
  inserted_at
  UNIQUE (quiz_id, tag) · INDEX (tag)

quiz_questions
  id uuid PK · quiz_id FK → quizzes ON DELETE CASCADE · position int
  type string · prompt text · accepted_answers string[] · difficulty string
  time_limit_ms int NULL · image_key string NULL · image_alt string NULL · explanation text NULL
  inserted_at · updated_at
  UNIQUE (quiz_id, position)

images
  id uuid PK · key string UNIQUE · content_type string · byte_size int
  owner_key_hash string · inserted_at
```

- **Only public quizzes are stored.** Private quizzes never reach the database.
- **Built-in quizzes** live as documents in `server/priv/quizzes/<slug>.json` and are
  synced into the database by slug (`mix run priv/repo/seeds.exs`, also run by `mix setup`).
  They are `source: builtin`, `visibility: public`, and have no publisher.
- **Image files** are stored under the configured uploads directory and served at
  `/uploads/<key>`. The database row records ownership for cleanup.
- **Future accounts:** add `quizzes.owner_user_id` (nullable) and claim existing quizzes
  by publisher key; the document is unchanged.

## 4. Private and public quizzes (no accounts)

- **Private** (the default when creating): the quiz lives only on the device that made it
  (the app's local database, photos included as `image.data`). Each time that device hosts
  it, the whole document is sent with room creation (§5.7); the server validates it, plays
  it, and forgets it (photos included) when the room closes. Friends play it by joining
  the room.
- **Public:** stored in the server database, listed for everyone and hostable by anyone.
  The device keeps its local copy (the one it edits) and remembers the published id.
- **Publishing is a submission, and a submission is a package.** Asking for a quiz to be
  public sends one `.fazoura` (§5.3b, §5.4) and it waits in a queue until somebody reads
  it (ADMIN.md §3.2). Until then there is no row in `quizzes` and no file in the uploads
  volume — which is what lets every query against `quizzes` mean "public" with no second
  condition to forget, and means nothing unreviewed can be found, hosted or served.
  Approval unpacks the package (§6, the path a dropped-in preset already takes) and only
  then is there a quiz. Waiting costs its author nothing: the quiz is still on their
  device and still hosted inline, which never touches the server's library at all.
- **An edit of a public quiz comes back through the queue too** (§5.5), offered against
  the quiz it replaces so approval swaps that quiz's contents rather than adding a second
  copy. Otherwise approval would mean nothing: publish something harmless, then change it.
  The published version stays exactly as it was while the edit waits, and a turned-down
  edit leaves it untouched.
- A rejection carries a note, sent only to the device that submitted it — it is a message
  to an author, not something published beside a quiz. A device asks for its own
  submissions with §5.4a, which is how it learns that a quiz went public: approval happens
  when somebody reads the queue, not while the app is open.
- Making a quiz private again deletes the stored copy (§5.6) and withdraws anything of it
  still waiting to be read, as does deleting it on the device — otherwise an admin could
  approve, and publish, a quiz its author had thrown away.
- Each app install generates a random **publisher key** (≥ 32 URL-safe characters) once
  and keeps it on the device. It is not an account: it is sent as the `x-owner-key` HTTP
  header and only proves "this device published it". The server stores
  `sha256(publisher_key)`. Only that key can replace or unpublish a published quiz.
  Built-in quizzes cannot be changed through the API. An explicit offline download is
  available to any client because offline hosting requires the accepted answers.
- Requests for a quiz that doesn't exist, or to change one someone else published, get
  `404 quiz_not_found`, never `403`.

## 5. REST API

JSON bodies; errors are `{"code": string, "message": string, "errors"?: {field: [msg]}}`.

### 5.1 `GET /api/quizzes`

Query: `q` (case-insensitive, matches the title **or** any tag), `tag` (exact tag, after
normalisation), `limit` (1–50, default 20), `offset`. Lists stored (public) quizzes;
`is_owner` is true for ones published with the request's `x-owner-key`.

```json
200 {"quizzes": [<quiz document without "questions">], "next_offset": 20 | null}
```

Order: built-in first, then most recently updated.

### 5.2 `GET /api/tags`

`tags` are the tags public quizzes actually use, most used first then alphabetically
(query: `limit`, 1–100, default 30). `suggested` is the admin-maintained quick-pick list
(§2.3, ADMIN.md §3.5); clients fall back to their built-in list when it is empty or the
server can't be reached.

```json
200 {
  "tags": [{"tag": "general", "count": 12}, {"tag": "pop culture", "count": 3}],
  "suggested": ["general", "science", "movies"]
}
```

### 5.3 `GET /api/quizzes/:id`

`:id` is the uuid or a built-in slug. Returns the document **without** `questions`, or
**with** them for the publisher.

### 5.3a `GET /api/quizzes/:id/download`

Explicitly downloads a public quiz for offline use. Returns the full document, including
accepted answers and remote image URLs. The client should download those images too and
store the resulting document privately on the device. This endpoint is intentionally an
opt-in answer disclosure: without the answers, the device could not host the quiz offline.

### 5.3b `GET /api/quizzes/:id/archive`

Explicitly downloads the same offline quiz as a `.fazoura` ZIP archive. The archive contains:

```text
manifest.json
media/<generated-image-key>
```

`manifest.json` contains the complete quiz document under `quiz`. Its question `image` objects
use `path` instead of `key` or `url`, pointing to files inside the archive. The archive therefore
keeps text, accepted answers and binary images together and can be retained or shared as one file.
Clients should verify and unpack it in memory or in their local cache before hosting. The JSON
download endpoint remains available for compatibility.

The same format goes the other way. An admin uploads one from the dashboard (ADMIN.md §3.3) to
add a quiz with its photos in a single step, and `tools/fazoura_pack.py` builds one from a folder
of JSON and images — so a quiz can be written offline, or moved from one server to another,
without publishing every photo by hand first:

```text
film-night/                          $ tools/fazoura_pack.py film-night
  film-night.json                    film-night.fazoura · 12 questions · 2 photos · 1409 KB
  media/matrix.jpg
```

A reader treats a package as hostile: it is capped in size, what it claims to expand to is
checked before anything is decompressed, entries outside `media/` are ignored, and its photos
are validated like any upload (§5.7) before they are stored. A photo is named inside the
package by a digest of its own bytes, so the same picture used twice is carried once.

### 5.4 `POST /api/quizzes` (submit for review)

Header `x-owner-key` required. `multipart/form-data` with one `file` part: a `.fazoura`
package (§5.3b) carrying the quiz and its photos. `201` with the submission document
below — **not** a quiz. Nothing is published, listed or written to the uploads volume
until an admin approves it (§4, ADMIN.md §3.2).

```json
201 {
  "id": "…", "title": "Movie Night", "status": "pending",
  "question_count": 12, "has_photos": true,
  "review_note": null, "quiz_id": null, "replaces_quiz_id": null,
  "submitted_at": "2026-09-23T10:00:00Z", "reviewed_at": null
}
```

`status` is `pending`, `approved` or `rejected`; `quiz_id` is filled in once there is a
published quiz. Errors: `401 owner_key_required` without a valid key;
`422 invalid_quiz` when the package carries no title or no questions;
`422 archive_too_large`, `422 invalid_archive`, `422 manifest_missing`,
`422 manifest_invalid` for a package that cannot be read.

A JSON document is refused with `422 package_required`. Rebuilding one server-side would
mean its photos had been uploaded first and were already on disk unreviewed, which is the
one thing the queue exists to prevent — so a client old enough to send one is told to
update instead, which it can do from inside the app.

### 5.4a `GET /api/submissions` and `DELETE /api/submissions/:id`

What this device has sent and what became of it, newest first. Its own only: the
`x-owner-key` header decides, and somebody else's submission does not exist to it.

```json
200 {"submissions": [<submission document>]}
```

`DELETE` withdraws one, `204`. Anything else is `404 not_found`, never `403`.

### 5.5 `PUT /api/quizzes/:id` (submit an edit)

Publisher only, and a submission like §5.4: `multipart/form-data` with one `file` part,
`200` with the submission document, `replaces_quiz_id` set to `:id`. The published quiz
is untouched while the edit waits. On approval it replaces that quiz — same id, all tags
and questions, question ids re-issued, `version` incremented — so a device that saved it,
or a room that has it selected, is looking at the same quiz rather than a second copy.

### 5.6 `DELETE /api/quizzes/:id` (unpublish)

Publisher only. `204`.

### 5.7 `POST /api/images`

Publisher key required. `multipart/form-data` with one `file` part: JPEG, PNG or WebP
(checked by content, not by filename), ≤ 2 MB. Clients downscale to at most 1280 px on
the longest side.

```json
201 {"key": "5b0e4f1c9a2d7e3f.jpg", "url": "https://…/uploads/5b0e4f1c9a2d7e3f.jpg"}
```

Errors: `413 image_too_large`, `415 unsupported_image`.

**No longer part of publishing.** A submission carries its photos inside the package, so
nothing is uploaded ahead of review. The endpoint remains for clients that predate the
queue and has no current caller.

### 5.8 Rooms

`POST /api/rooms` accepts either:

- `{"quiz_id": "<uuid or slug>"}`: a stored quiz (`pack_id` is still accepted as an
  alias); `404 quiz_not_found` if missing.
- `{"quiz": <quiz document>}`: a **private quiz sent inline**. It is validated like §5.4
  (`422 invalid_quiz`) but not stored. Photos come as `image.data` (base64; `key` is
  ignored; `413 image_too_large`, `415 unsupported_image`). The server keeps them in memory
  and serves them at `/api/room-images/<random key>` until the room closes. Request bodies
  may be up to 32 MB.

The room snapshots the quiz and starts with its `default_settings`. A question's photo URL
becomes the room state's `question.image_url` (PROTOCOL.md §5.1).

A **LAN host** does the same thing on its own origin. It has no quiz database and no
internet, so every quiz reaches it as a document inline with `host_select_quiz`, photos and
all; it keeps them in memory under random keys and serves them from the port it is already
listening on, at `http://<host-ip>:<port>/api/room-images/<key>`, with the same per-image
(2 MB) and per-room (8 MB) limits and the same response headers. A photo it will not accept
fails the intent with `invalid_quiz`, the code Cloud answers with for the same document.
Clients cannot tell the two apart: both send an ordinary `image_url`.


## 6. Presets

A preset is an ordinary public quiz. Nothing about it is a separate kind of thing: same
table, same photos in the uploads directory, same sweeper, same browsing. It carries two
extras — `source: "builtin"`, which shows it first when browsing, and a `slug`, which makes
it hostable by name — and an admin can set or clear both on any published quiz from the
dashboard (ADMIN.md).

The ones that ship with the server live in `server/priv/quizzes/`, one JSON file per quiz,
and are synced on every deploy by `Fazoura.Quizzes.sync_builtin!/1`:

- **The filename is the slug.** `film-night.json` is hostable as `{"quiz_id": "film-night"}`.
- **The file holds a quiz document** (§2) without the output-only fields — the sync assigns
  `source`, `visibility` and the rest.
- **Photos sit beside it**, named by `image.path` relative to the quizzes directory:

  ```json
  "image": { "path": "media/matrix.jpg", "alt": "A man dodging bullets" }
  ```

  The sync reads the file, validates it like any upload, and stores it under a key derived
  from its own bytes — so re-running reuses the same file instead of leaving the previous
  copy behind. A path that escapes the quizzes directory, a file that is missing, or one
  that is not a JPEG/PNG/WebP stops the sync: these run on every deploy, and a preset with
  a hole in it should stop the release rather than reach a party.
- **`version` is not bumped for you.** Change the questions and change `"1.0"` to `"1.1"`,
  or devices holding an offline copy will not know it is stale.

A folder in this layout is also exactly what `tools/fazoura_pack.py` packs, so a preset can be
handed to another server as one `.fazoura` file without going through the repository (§5.3b).

### Packages dropped in

A quiz can also ship as a `.fazoura` package instead of as a JSON document with photos beside
it. `Fazoura.Quizzes.sync_packages!/0` reads every `<slug>.fazoura` in **two** directories and
upserts each exactly as a built-in, alongside the JSON files:

1. `:packages_dir` — `server/priv/packages`, committed and carried in the image, which is
   where a quiz that ships with the server lives.
2. `:packages_drop_dir` — `PACKAGES_DIR`, unset by default. A directory on the server, so a
   quiz can be added or corrected without rebuilding the image.

It reads them in that order, so a dropped package with the same slug as a shipped one wins —
which is the only way to correct a shipped quiz without a deploy. Both run from
`priv/repo/seeds.exs` and from `Fazoura.Release.setup/0`, so every deploy re-applies them.

- **The filename is the slug**, so re-running updates the quiz a package already made rather
  than adding another, and replacing the file replaces the quiz.
- **The package carries its photos**, so unlike a JSON preset nothing has to be published
  first; they are stored on the way in like any other upload (§5.3b).
- **A package that cannot be read stops the sync.** These run on a deploy, and a quiz someone
  put there going quietly missing is worse than a release that stops.
- **A directory that isn't there is simply no packages**, so a server that uses none needs no
  configuration.

Pointing `PACKAGES_DIR` at a mounted directory is what makes the second one a drop folder:
copy a package onto the server, run the seed, and the quiz is there — no image to rebuild.

A package is one file with its photos inside, so it is the easier of the two to move between
servers, to hand to someone, or to produce from a folder (`tools/fazoura_pack.py`). A JSON
document with a `media/` directory beside it stays readable in a diff, which a ZIP is not.

Preset photos are owned by a key no device holds, so nobody can edit or unpublish a preset
through the API and no other quiz can reference its photos. The repository is what changes
them, and re-running the sync restores them if the uploads volume is ever lost.

## 7. Evolution checklist

- New optional field → add to this doc, the changeset and the Dart model with a default.
  No version bump.
- New suggested tag → an admin adds it in the dashboard; no release needed. Changing the
  built-in fallback means editing §2.3, `Fazoura.Quizzes.Tag` and the Dart constant.
- New question `type` → document its fields; old clients skip unknown types when listing
  and the server refuses to start a room on a client that can't play it (future
  `min_client_version`).
- Breaking change → bump `format_version`, keep reading the previous version on import,
  and write a data migration.
