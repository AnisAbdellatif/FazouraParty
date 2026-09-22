# Preparing a quiz folder

A practical guide for writing a Fazoura quiz by hand — for a person or for an LLM asked to
produce one. It covers the folder to build, what the JSON file must contain, where the photos
go, and how to turn the folder into something the app or the server will take.

The authority on the format is [QUIZ_FORMAT.md](QUIZ_FORMAT.md); this file is the how-to. If
the two ever disagree, QUIZ_FORMAT.md wins.

---

## 1. What you are building

One folder holding **one quiz document** (a `.json` file) and, if the quiz has photo
questions, the **image files beside it**:

```text
film-night/
  film-night.json          the quiz document
  media/
    matrix.jpg             one file per photo question
    casablanca.png
```

That folder is the source form. From it you get one of three things:

| You want | Do this |
|---|---|
| A single shareable file (`.fazoura`) to import in the app or upload in the admin dashboard | run `tools/fazoura_pack.py` (§6) |
| A preset that ships with the server | drop the same layout into `server/priv/quizzes/` (§7) |
| A quiz on someone's device | import the `.fazoura` in the app |

The folder name, the JSON file name and the `media/` folder name are yours to choose — except
for a preset, where **the JSON file name is the slug** (`film-night.json` → hostable as
`film-night`). `manifest.json` and `package.json` are reserved names; don't use them for the
quiz document.

---

## 2. The quiz document

A complete, minimal example — copy this shape:

```json
{
  "format_version": 1,
  "version": "1.0",
  "title": "Film Night",
  "description": "Blockbusters from the last thirty years.",
  "language": "en",
  "tags": ["movies", "cinema", "2000s"],
  "default_settings": {
    "time_limit_ms": 30000,
    "difficulty_multiplier": false
  },
  "questions": [
    {
      "type": "text",
      "prompt": "Who directed Jurassic Park?",
      "accepted_answers": ["Steven Spielberg", "Spielberg"],
      "difficulty": "easy",
      "image": null,
      "explanation": null
    },
    {
      "type": "text_photo",
      "prompt": "Which film is this still from?",
      "accepted_answers": ["The Matrix", "Matrix"],
      "difficulty": "medium",
      "image": {
        "path": "media/matrix.jpg",
        "alt": "A man in a long black coat dodging bullets"
      },
      "explanation": "The bullet-time scene, 1999."
    }
  ]
}
```

### 2.1 Quiz fields — what to write

| Field | Write it? | Rules |
|---|---|---|
| `format_version` | **required** | Exactly `1`. A document without it is refused. |
| `version` | recommended | `"<major>.<minor>"`, start at `"1.0"`. Bump the minor part whenever you change the questions, or devices holding an offline copy won't know their copy is stale. **Nothing bumps it for you.** |
| `title` | **required** | 1–80 characters after trimming. |
| `description` | optional | ≤ 280 characters, or `null`. |
| `language` | optional | BCP-47-ish, 2–10 characters. Defaults to `"en"`. Use the language the *questions* are in (`"ar"`, `"fr"`, …). |
| `tags` | **required** | 1–10 free-text tags, each 1–24 characters, in display order. Lower-cased, whitespace-collapsed and de-duplicated by the server, so `"Pop  Culture"` and `"pop culture"` are one tag. The **first tag picks the quiz card's colour** in the app, so put the broadest one first. Suggested quick picks: `general`, `science`, `history`, `geography`, `movies`, `tv`, `music`, `sports`, `food`, `nature`, `technology`, `art`, `books`, `gaming`, `pop culture`, `language` — a convenience, not a closed list. |
| `default_settings` | optional | `time_limit_ms` (10000–120000, default 30000) and `difficulty_multiplier` (bool, default `false`). These pre-fill the lobby; the host can still change them. |
| `questions` | **required** | 1–1024 questions, in play order. |

**Leave these out.** They are assigned by the server and ignored (or overwritten) on input:
`id`, `slug`, `source`, `visibility`, `is_owner`, `question_count`, `has_photos`,
`created_at`, `updated_at`, and every question's `id`. Writing them does no harm, but they
are noise — and a `question_count` that disagrees with the array is worse than absent.

Unknown keys are ignored rather than rejected, so an extra field carrying provenance
(`"source_pack_id": 292783`) survives in your source file without breaking anything — it just
won't be stored.

### 2.2 Question fields

| Field | Write it? | Rules |
|---|---|---|
| `type` | **required** | `"text"` or `"text_photo"`. Nothing else exists yet. |
| `prompt` | **required** | 1–280 characters. The question as players see it. |
| `accepted_answers` | **required** | 1–10 strings, each 1–100 characters. See §4 — this is the field that decides whether the quiz is fun. |
| `difficulty` | recommended | `"easy"`, `"medium"` or `"hard"`. Defaults to `"easy"`. Only matters when the host turns difficulty scoring on, where it sets what the question is worth: easy +10 / −15, medium +25 / −10, hard +50 / −5. |
| `image` | see §3 | **Required for `text_photo`, must be `null` (or absent) for `text`.** |
| `explanation` | optional | ≤ 280 characters, shown after the reveal in a later release. `null` is fine. |
| `time_limit_ms` | skip it | Reserved for per-question overrides; rooms ignore it today. |

The order of `questions` is the play order for presets, but a room draws its questions at
random from the pool when the host picks several quizzes — don't write questions that depend
on the one before them.

---

## 3. Photos

### 3.1 Where the files go

A `text_photo` question names its file with a **path relative to the folder**:

```json
"image": { "path": "media/matrix.jpg", "alt": "A man dodging bullets" }
```

- `media/` is a convention, not a rule — `images/poster.jpg` works the same. Keep them all in
  one subfolder so the folder stays readable.
- The path must stay **inside the folder**. A `..` that climbs out is refused, whatever the
  spelling.
- Two questions may point at the same file. It is carried once (photos are named inside the
  package by a digest of their own bytes), so reusing a picture costs nothing.
- `key` and `url` mean something only on a running server. Don't write them by hand; if a
  document you're editing has them, they are dropped when the folder is packed.
- `alt` is optional, ≤ 140 characters. Write it — it's what a screen reader announces, and it
  must not give the answer away.

Instead of `path`, a question may carry `"data"` with base64 image bytes (that is how the app
keeps photos on a device). Both work, but for a folder you're writing by hand, `path` is the
one to use — a base64 blob makes the JSON unreadable and unreviewable.

### 3.2 What the files must be

These are the server's upload rules, and the packer applies exactly the same ones, so a folder
that packs is a folder the server will take:

- **JPEG, PNG or WebP** — checked by the file's own bytes, not by its extension. A PNG named
  `.jpg` is fine; a `.jpg` that is really a HEIC or a GIF is refused.
- **≤ 2 MB per photo.**
- **≤ 32 MB for the whole package.** Photos dominate that budget: roughly twenty 1.5 MB photos
  and you are at the ceiling.
- Downscale to at most **1280 px on the longest side** before packing. That is what the app
  does when it uploads, it is more than enough on a phone, and it is the easiest way to stay
  under both limits.

Resizing a folder of photos in one go:

```bash
mogrify -resize 1280x1280\> -quality 82 media/*.jpg
```

---

## 4. Writing answers that match

Answer checking is deliberately literal. The server normalizes both sides and compares them
exactly — **there is no fuzzy or near-miss matching.** Normalization is:

1. Unicode NFD decomposition, then every combining mark removed — so accents don't matter
   (`café` = `cafe`).
2. Case folding — so capitals don't matter.
3. Outer whitespace trimmed, inner runs of whitespace collapsed to one space.

**Punctuation is not stripped.** `Saint John's` and `Saint Johns` are two different answers.

So the whole burden is on `accepted_answers`. List every form a player might reasonably type,
up to ten:

```json
"accepted_answers": ["Steven Spielberg", "Spielberg"]
"accepted_answers": ["6", "six"]
"accepted_answers": ["Saint John's", "Saint Johns", "St John's", "St. John's"]
"accepted_answers": ["The Matrix", "Matrix"]
```

Rules of thumb:

- **Surname alone**, when it is unambiguous in context.
- **Both spellings** when an apostrophe, hyphen or period is in play.
- **Digits and the word** for numbers.
- **With and without a leading article** (`The Matrix` / `Matrix`).
- **Common transliterations** for names crossing scripts.
- Don't bother with accent or case variants — normalization already handles those.

The host override is the safety net: after a question ends, the host sees the accepted answers
and can mark any submission right or wrong, which re-applies the score immediately. Good
`accepted_answers` mean the host rarely has to.

Two more things worth knowing while writing prompts:

- **Nobody sees the accepted answers before a question ends** — not even the host, who may be
  playing. So a prompt has to stand on its own.
- A question scores by its difficulty, and a wrong answer costs **more** on an easy question
  than on a hard one (PROTOCOL.md §9). So label difficulty honestly: marking a genuinely hard
  question "easy" punishes the room twice over. A quiz also reads better when difficulty
  varies.

---

## 5. Checking the folder before you pack

Quick sanity pass on a document you just wrote:

```bash
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); qs=d["questions"]; print(len(qs),"questions,",sum(1 for q in qs if q["type"]=="text_photo"),"photos"); print("bad type:",[i for i,q in enumerate(qs,1) if q["type"] not in ("text","text_photo")]); print("no answers:",[i for i,q in enumerate(qs,1) if not q.get("accepted_answers")]); print("photo without image:",[i for i,q in enumerate(qs,1) if q["type"]=="text_photo" and not q.get("image")])' film-night/film-night.json
```

The packer repeats these checks and more, and points at the question number that is wrong — so
the real check is just to pack it.

---

## 6. Packing it

```bash
tools/fazoura_pack.py film-night
```

```text
film-night.fazoura · 12 questions · 2 photos · 1409 KB
```

- Writes `film-night.fazoura` beside the folder (`-o` to put it elsewhere).
- Finds the quiz document by itself when the folder holds exactly one `.json`; name it with
  `-q` when there is more than one.
- Standard-library Python 3.9+, nothing to install.
- Deterministic: packing the same folder twice gives a byte-identical file.

The package it writes is a ZIP containing `manifest.json` (the document, under a `quiz` key)
and `media/<hash>.<ext>` for each photo. It is the same format `GET /api/quizzes/:id/archive`
sends, so a quiz can be exported from one server and imported into another.

Common failures and what they mean:

| Message | Fix |
|---|---|
| `the document needs "format_version": 1` | Add the field, value `1`. |
| `the document needs 1 to 10 tags` | `tags` is required — at least one. |
| `question 7: a text_photo question needs an image` | Either add `image`, or make it `"type": "text"`. |
| `question 7: only a text_photo question may carry an image` | A `text` question has an `image` — set it to `null`, or change the type. |
| `question 7: media/x.jpg: No such file or directory` | The path is wrong or relative to the wrong place: it is relative to the **folder**, not to the JSON file's directory (the same thing when the JSON sits at the folder root). |
| `question 7: the photo is not a JPEG, PNG or WebP` | It is a HEIC, GIF, SVG or a renamed something. Convert it. |
| `question 7: the photo is 3.4 MB, over the 2 MB limit` | Downscale (§3.2). |
| `the package is 36.2 MB, over the 32 MB the server reads` | Fewer or smaller photos. |
| `holds several documents (…) — name one with --quiz` | Pass `-q film-night/film-night.json`. |

---

## 7. Getting the quiz in

**As a file you share or import.** Hand someone the `.fazoura`; the app reads it and keeps the
quiz on the device. A quiz kept that way is *private* — it never reaches the server database,
and each time the device hosts it, the whole document travels with the room and is forgotten
when the room closes.

**As a preset shipped with the server.** Put the folder's contents into
`server/priv/quizzes/` — the document as `<slug>.json` at the top, its photos under the path
each `image.path` names, relative to `server/priv/quizzes/`:

```text
server/priv/quizzes/
  film-night.json
  media/matrix.jpg
```

`priv/repo/seeds.exs` syncs them into the database on every deploy, keyed by slug, and stores
the photos as ordinary uploads. A missing or invalid photo **stops the sync** rather than
shipping a preset with a hole in it. Remember to bump `version` when you change the questions.

```bash
cd server && mix run priv/repo/seeds.exs
```

**As an upload to a running server.** The admin dashboard (`/admin/quizzes`) takes a
`.fazoura` directly — photos and all — and adds it as a preset. Pasting the bare JSON works
too, but then the photos must already have been uploaded and referenced by `key`, which is why
the package is the easier path.

---

## 8. Checklist

- [ ] `format_version` is `1`, `version` is set (and bumped if this is a revision).
- [ ] `title` ≤ 80 characters; 1–10 `tags`, broadest first.
- [ ] Every question has a `prompt` and at least one accepted answer.
- [ ] `accepted_answers` lists the realistic spellings, not just the canonical one.
- [ ] `type` is `text` or `text_photo`; `image` is `null` on every `text` question.
- [ ] Every `image.path` points at a file that exists inside the folder, ≤ 2 MB, JPEG/PNG/WebP,
      ≤ 1280 px on the longest side.
- [ ] `alt` written, and it doesn't give the answer away.
- [ ] No `id`, `slug`, `source`, `visibility`, `question_count`, `has_photos`, `created_at` or
      `updated_at`.
- [ ] `tools/fazoura_pack.py <folder>` succeeds and reports the question and photo counts you
      expect.
