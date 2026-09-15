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
4. **No answer leaks.** Accepted answers are only sent to the quiz's owner, never to
   people browsing public quizzes (they may end up playing it).
5. **Accounts later.** Ownership is a per-device secret today; the model leaves room for a
   user id without changing the document.

## 2. Quiz document (format version 1)

```json
{
  "format_version": 1,
  "id": "3f0c2a5e-6b1e-4f0a-9d8e-2b7c1e4a9f10",
  "slug": null,
  "title": "Movie Night",
  "description": "Blockbusters from the last 30 years.",
  "language": "en",
  "category": "movies",
  "tags": ["cinema", "2000s"],
  "source": "custom",
  "visibility": "private",
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
| `id` | uuid string | Server-assigned; ignored on create |
| `slug` | string \| null | Stable human id for built-in quizzes (`general-knowledge`); `null` for custom |
| `title` | string | Required, 1–80 characters (trimmed) |
| `description` | string \| null | ≤ 280 characters |
| `language` | string | BCP-47-ish code, 2–10 chars, default `"en"` |
| `category` | string | One of §2.3, default `"general"` |
| `tags` | string[] | ≤ 10 tags, each 1–24 chars, lower-cased |
| `source` | `"builtin"` \| `"custom"` | Server-assigned |
| `visibility` | `"public"` \| `"private"` | Required on create; changeable by the owner (§4) |
| `is_owner` | bool | Output only: whether the request's owner key owns this quiz |
| `default_settings` | object | Suggested room settings. `time_limit_ms` 10 000–120 000 (default 30 000), `difficulty_multiplier` bool (default false). Rooms start with these; the host can still change them in the lobby |
| `question_count` | int | Output only |
| `has_photos` | bool | Output only: at least one `text_photo` question |
| `created_at`, `updated_at` | ISO 8601 UTC | Output only |
| `questions` | Question[] | Required on create/replace: 1–100 questions, in play order |

### 2.2 Question fields

| Field | Type | Rules |
|---|---|---|
| `id` | uuid string | Server-assigned; stable across edits only while the quiz exists |
| `type` | `"text"` \| `"text_photo"` | Required. Future types (e.g. `multiple_choice`) will add fields; readers must skip question types they don't know |
| `prompt` | string | Required, 1–280 characters |
| `accepted_answers` | string[] | Required, 1–10 answers, each 1–100 characters. Matching is PROTOCOL.md §8 |
| `difficulty` | `"easy"` \| `"medium"` \| `"hard"` | Default `"easy"`; drives the difficulty bonus (PROTOCOL.md §9) |
| `time_limit_ms` | int \| null | Reserved for per-question overrides; ignored by rooms today |
| `image` | object \| null | Required for `text_photo`, must be `null` for `text`. On input only `key` (from §5.6) and optional `alt` (≤ 140 chars); `url` is output only |
| `explanation` | string \| null | ≤ 280 chars, shown after the reveal in a later release |

### 2.3 Categories

`general`, `science`, `history`, `geography`, `movies`, `music`, `sports`, `food`,
`language`, `pop_culture`, `other`. New categories may be added without a version bump;
clients show unknown ones as "Other".

## 3. Storage (Ecto)

Portable across SQLite and Postgres: no Postgres-only SQL, string enums (validated in
changesets), arrays via Ecto's `{:array, :string}`.

```
quizzes
  id uuid PK · slug string UNIQUE NULL · format_version int
  title string · description text NULL · language string · category string · tags string[]
  source string · visibility string · owner_key_hash string NULL (sha256 hex)
  default_time_limit_ms int · default_difficulty_multiplier bool
  question_count int · has_photos bool (denormalised for listing)
  inserted_at · updated_at
  INDEX (visibility, updated_at) · INDEX (owner_key_hash)

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

- **Built-in quizzes** live as documents in `server/priv/quizzes/<slug>.json` and are
  synced into the database by slug (`mix run priv/repo/seeds.exs`, also run by `mix setup`).
  They are `source: builtin`, `visibility: public`, and have no owner.
- **Image files** are stored under the configured uploads directory and served at
  `/uploads/<key>`. The database row records ownership for cleanup.
- **Future accounts:** add `quizzes.owner_user_id` (nullable) and claim existing quizzes
  by owner key; the document is unchanged.

## 4. Ownership and visibility (no accounts yet)

- Each app install generates a random **owner key** (≥ 32 URL-safe characters) once and
  keeps it on the device. It is sent as the `x-owner-key` HTTP header. The server stores
  only `sha256(owner_key)`.
- Creating a quiz requires an owner key; that key owns it.
- `public` quizzes: listed for everyone and hostable by anyone.
- `private` quizzes: listed only for the owner and hostable only by the owner. Friends
  still play them by joining the owner's room.
- Only the owner can read accepted answers, edit, change visibility or delete.
  Built-in quizzes cannot be edited through the API.
- A request for a quiz the caller can't see gets `404 quiz_not_found` — never `403` —
  so private quizzes can't be probed.

## 5. REST API

JSON bodies; errors are `{"code": string, "message": string, "errors"?: {field: [msg]}}`.

### 5.1 `GET /api/quizzes`

Query: `scope=public|mine` (default `public`; `mine` requires `x-owner-key`),
`q` (case-insensitive title search), `category`, `limit` (1–50, default 20), `offset`.

```json
200 {"quizzes": [<quiz document without "questions">], "next_offset": 20 | null}
```

Order: built-in first, then most recently updated.

### 5.2 `GET /api/quizzes/:id`

`:id` is the uuid or a built-in slug. Returns the document **without** `questions` for
non-owners (built-ins included), and **with** `questions` for the owner.

### 5.3 `POST /api/quizzes`

Header `x-owner-key` required. Body: a quiz document (server-assigned and output-only
fields ignored). `201` with the full document. `422 invalid_quiz` with `errors` on
validation failure; `401 owner_key_required` without a valid key.

### 5.4 `PUT /api/quizzes/:id`

Owner only. Replaces the quiz, including all questions (question ids are re-issued).
`200` with the full document.

### 5.5 `PATCH /api/quizzes/:id` · `DELETE /api/quizzes/:id`

Owner only. `PATCH` accepts `{"visibility": "public" | "private"}` → `200` document.
`DELETE` → `204`.

### 5.6 `POST /api/images`

Owner key required. `multipart/form-data` with one `file` part: JPEG, PNG or WebP
(checked by content, not by filename), ≤ 2 MB. Clients downscale to at most 1280 px on
the longest side before uploading.

```json
201 {"key": "5b0e4f1c9a2d7e3f.jpg", "url": "https://…/uploads/5b0e4f1c9a2d7e3f.jpg"}
```

Errors: `413 image_too_large`, `415 unsupported_image`.

### 5.7 Rooms

`POST /api/rooms` accepts `{"quiz_id": "<uuid or slug>"}` (`pack_id` is still accepted as
an alias) plus the optional `x-owner-key` header, needed to host a private quiz. The room
snapshots the quiz and starts with its `default_settings`. A question's `image.url` becomes
the room state's `question.image_url` (PROTOCOL.md §5.1).

## 6. Evolution checklist

- New optional field → add to this doc, the changeset and the Dart model with a default.
  No version bump.
- New question `type` → document its fields; old clients skip unknown types when listing
  and the server refuses to start a room on a client that can't play it (future
  `min_client_version`).
- Breaking change → bump `format_version`, keep reading the previous version on import,
  and write a data migration.
