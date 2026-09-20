# Fazoura Party — Quiz format, storage and API

**Quiz format version: `1`** · Companion to [PROTOCOL.md](PROTOCOL.md) (which covers live rooms).

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
| `language` | string | BCP-47-ish code, 2–10 chars, default `"en"` |
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
| `image` | object \| null | Required for `text_photo`, must be `null` for `text`. Fields: `key` (from §5.6, when publishing); `data` (base64 JPEG/PNG/WebP ≤ 2 MB, for private quizzes sent inline, §5.7, and how the app keeps photos on the device); `path` (a file beside the document — inside a `.fazoura` archive, §5.3b, or beside a preset's JSON, §6); optional `alt` (≤ 140 chars); `url` is output only |
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
- **Public:** the device publishes the document (§5.3) and it is stored in the server
  database, listed for everyone and hostable by anyone. The device keeps its local copy
  (the one it edits) and remembers the published id.
- The creator can switch at any time: publishing uploads photos (§5.6) and creates or
  replaces the stored copy; making it private again deletes the stored copy (§5.5).
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
(§2.3, ADMIN.md §3.3); clients fall back to their built-in list when it is empty or the
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

The same format goes the other way. An admin uploads one from the dashboard (ADMIN.md §3.2) to
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

### 5.4 `POST /api/quizzes` (publish)

Header `x-owner-key` required. Body: a quiz document (server-assigned and output-only
fields ignored; photos by `key`). `201` with the full document. `422 invalid_quiz` with
`errors` on validation failure; `401 owner_key_required` without a valid key;
`422 unknown_image` if a photo key wasn't uploaded with the same key.

### 5.5 `PUT /api/quizzes/:id`

Publisher only. Replaces the quiz, including all tags and questions (question ids are
re-issued), and increments `version`. `200` with the full document.

### 5.6 `DELETE /api/quizzes/:id` (unpublish)

Publisher only. `204`.

### 5.7 `POST /api/images`

Publisher key required. `multipart/form-data` with one `file` part: JPEG, PNG or WebP
(checked by content, not by filename), ≤ 2 MB. Clients downscale to at most 1280 px on
the longest side. Only needed to publish.

```json
201 {"key": "5b0e4f1c9a2d7e3f.jpg", "url": "https://…/uploads/5b0e4f1c9a2d7e3f.jpg"}
```

Errors: `413 image_too_large`, `415 unsupported_image`.

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
