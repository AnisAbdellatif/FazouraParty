# Fazoura Party — Admin dashboard

Companion to [PROTOCOL.md](PROTOCOL.md) (live rooms) and [QUIZ_FORMAT.md](QUIZ_FORMAT.md)
(quizzes). The dashboard is served by the game server itself at **`/admin`**.

---

## 1. Why it lives in Phoenix

The key indicators are live data: running games and connected players are BEAM processes in
the room registry, not rows in a table. The Phoenix server can read them directly, so the
dashboard is five LiveViews in the same application — no second service to deploy, no
extra API to expose the room state, no second set of credentials or CORS rules. The quiz
database is already here too.

The only JavaScript is the LiveView client, served straight from the dependencies
(`/admin/js/…`); the project has no asset pipeline and doesn't need one.

## 2. Access

- Credentials come from the environment: **`ADMIN_USERNAME`** and **`ADMIN_PASSWORD`**
  (`config :fazoura, :admin` — `config/dev.exs` sets `admin` / `admin` for local work).
- HTTP Basic auth over the whole `/admin` scope. Failures are `401`.
- **With either variable unset the dashboard does not exist:** every `/admin` request is a
  plain `404`, so a deployment that forgot to configure it can't be logged into and doesn't
  advertise that an admin area is there.
- The websocket carries no Basic auth header, so the authenticated HTTP request leaves a
  flag in the session and each LiveView checks it on mount.
- There is one admin identity, not accounts: enough for a party game, and it keeps the
  attack surface to one password.

## 3. Tabs


### 3.1 Stats (`/admin`)

Refreshes every 2 seconds while open.

- **Live now:** running games, connected players, players seated in a game, games hosted
  since the server started (a counter in memory, so it resets with the node).
- **Rooms:** every running room — code, quiz, phase, question x/y, players, connections.
- **Library:** public quizzes (presets vs community), questions (and how many have photos),
  distinct tags, uploaded images.
- **Most used tags** and the **newest quizzes**.

### 3.2 Review (`/admin/review`)

The queue between somebody writing a quiz and it being public (QUIZ_FORMAT.md §4). Nothing
here is a quiz: a submission is the `.fazoura` package a device sent, and its photos are
not in the uploads volume. That is the point — there is nothing for a listing, a room or
the photo store to find until it has been read.

- Waiting submissions, oldest first, with a count in the tab.
- **Read** opens one: the package is inflated here and nowhere else, showing every prompt,
  its accepted answers, the tags and each photo. Photos are served from the package by
  `GET /admin/submissions/:id/photo?path=…`, behind the same credentials, `no-store` and
  never sniffed — they are bytes a stranger uploaded that nobody has vouched for yet.
- **Approve and publish** unpacks it through the same path a dropped-in preset takes, so an
  approved community quiz is stored exactly like a shipped one. Its photos reach the
  uploads volume here and not before.
- **Turn down** keeps the row and the reason, which the submitting device reads back from
  `GET /api/submissions`. The package is dropped either way once it has been decided.

Approve only exists once a submission is open: there is no way to publish one from the list
without having read it.

### 3.3 Reports (`/admin/reports`)

The other end of the review queue. Review reads a quiz before it goes out; this hears
about the ones that got through — because a reader was wrong, or because the author
edited it afterwards into something else (QUIZ_FORMAT.md §5.9).

Google Play requires an in-app way to report user content and a timely answer to it, so
this is a queue with a clock on it rather than a mailbox.

- Reported quizzes, longest-waiting first, with a count in the tab. A quiz's place is set
  by the **first** person who complained about it, not the most recent, so a pile-on
  cannot push an older complaint down the list.
- Each row carries how many people reported it and why. One device counts once however
  many times it taps, so the number means people.
- **Read** opens it: every reason and note given, and the quiz itself — prompts, accepted
  answers and photos — because deciding whether something should be public means looking
  at it, not at a title.
- Anything left longer than a day is called out in the list, since that is the window Play
  expects an answer in.
- **Take it down** deletes the quiz, and its reports go with it. **Keep it** answers every
  open report and leaves the quiz public. **Edit it instead** opens the editor (§3.5), for
  a quiz that needs one question removed rather than deleting altogether — the reports stay
  open until answered either way.

Like approving a submission, both answers exist only once a report is open: there is no
answering one from the list without having read it.

### 3.4 Quizzes (`/admin/quizzes`)

- Search by title or tag.
- **Make preset / Unset preset.** A preset is `source: "builtin"`: it gets a slug, is
  hostable by that slug and is listed first when browsing. Promoting a community quiz keeps
  its questions and tags; slugs are derived from the title and de-duplicated (`movie-night`,
  `movie-night-2`).
- **Upload a package.** One button: it opens the file dialog, and choosing a `.fazoura`
  (QUIZ_FORMAT.md §5.3b) imports it and opens it in the editor. There is nothing to confirm
  about a file that was just chosen from a dialog.
- **Download** any quiz as a `.fazoura`, photos included — for a backup, or to move it to
  another server, where it can be uploaded here or dropped in the packages directory (§6).
  The public `GET /api/quizzes/:id/archive` sends the same bytes but is metered at ten a
  minute; this route answers to the dashboard's credentials instead.
- **Add a preset** either by uploading that package or by pasting a quiz document (§2) — the same JSON as `server/priv/quizzes/*.json`. No publisher key
  is involved and photo keys are trusted. A package carries its photos, so they arrive with the
  quiz and become ordinary uploads owned by a key no device holds (§6); a pasted document does
  not, so its photos must already be uploaded. `tools/fazoura_pack.py` builds a package from a
  folder of JSON and images.
- **Edit** any quiz — its metadata and every question — in the editor (§3.5). A quiz added
  from a package or a pasted document opens there straight away, since a new quiz is the one
  most likely to need a correction before anyone plays it.
- **Delete** any quiz, preset or community, with its questions and tags. Running games are
  unaffected: a room snapshots its quiz when it starts (PROTOCOL.md §6.2).

Moderation deliberately ignores the publisher key that normally guards a quiz
(QUIZ_FORMAT.md §4).

### 3.5 Quiz editor (`/admin/quizzes/:id/edit`)

Everything about one quiz, community or preset.

- **Metadata:** title, description, language, tags (comma separated) and the default
  seconds per question and difficulty bonus. The form counts seconds; the document counts
  milliseconds (QUIZ_FORMAT.md §2.2).
- **Questions:** prompt, accepted answers (one per line, trimmed, blanks dropped),
  difficulty, an optional per-question time, an optional explanation — and add, remove and
  reorder.
- **One question is open at a time.** The rest are one-line rows: number, thumbnail,
  prompt, difficulty and the reorder and remove buttons. A shipped quiz can have 195
  questions, and rendering every field of every one is a page nobody can use and a diff on
  every keystroke that carries the whole form. A closed question keeps what was typed into
  it — the working copy is in the LiveView, not in the rendered inputs — and Save sits in a
  bar that stays at the top of the page.
- **Photos:** upload one per question, replace it, or remove it. Previews are served from
  this server's own origin (`/uploads/<key>`), never from the endpoint's public URL — behind
  a proxy those differ, and an absolute one points where the browser reading this page
  cannot follow. An uploaded photo is an
  ordinary upload owned by the server itself, the same owner a preset's photos have (§6), so
  it cannot be claimed or unpublished through the API. Removing one only drops the
  reference; `ImageSweeper` collects the file once nothing points at it.
- **A question's type follows its photo.** `text_photo` exactly when there is one, so a
  photo question with no photo is not a state the editor can produce.
- **Saving replaces the quiz** and bumps the minor version, exactly as `PUT /api/quizzes/:id`
  does for a publisher — question ids are re-issued, and a device holding an offline copy can
  tell that its copy is stale. Validation is `Quiz.changeset/2`, the same rules the API
  applies; a rejected save changes nothing and reports why.

- **Right-to-left content** is handled by `dir="auto"` on every field and on anything showing
  a quiz's own words, so an Arabic title, prompt or answer reads from the right without the
  dashboard itself becoming an Arabic dashboard.

The working copy lives in the LiveView until it is saved, so leaving the page discards it.

### 3.6 Tags (`/admin/tags`)

The **suggested tags** the apps offer as quick picks (QUIZ_FORMAT.md §2.3): add, remove,
reorder, and reset to the built-in list. Each tag shows how many public quizzes use it.
Saving is immediate; the apps pick changes up the next time they call `GET /api/tags`.

People can still type any tag they like — this list is a convenience, not a whitelist.

## 4. Storage

Editable settings live in one small table, as JSON text, so a new setting needs no
migration:

```
app_settings
  key string PK · value text · inserted_at · updated_at
```

`suggested_tags` is the only key today. Reading falls back to the code default
(`Fazoura.Quizzes.Tag.default_suggested/0`), which is what a fresh database uses.

## 5. Adding a tab

1. A LiveView in `server/lib/fazoura_web/live/admin/`, `use FazouraWeb, :live_view`, with a
   `page:` assign for the nav.
2. A `live` route inside the `live_session :admin` block in the router.
3. Read and write through `Fazoura.Admin` (or `Fazoura.Settings`), not `Repo` directly, so
   the rules stay in one place and stay testable.
