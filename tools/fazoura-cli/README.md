# fazoura — the game from a terminal

`fazoura` does what the app does — host a room, join one, answer, run the quiz library,
publish, pack `.fazoura` files — so a game can be played, scripted and checked without driving
a browser or a phone. One instance is one or more devices; run several to fill a room.

It is not a second client. The API calls, the Phoenix connection, the models, the `.fazoura`
format and the LAN host are the app's own (`app/lib/core`), imported as a package. What it
adds is a terminal around them: output, typed commands and bots.

## Running it

```bash
tools/fazoura-cli/fazoura --help
```

It needs the Flutter SDK the app uses (the app package declares Flutter, so resolving it
does), and nothing else. The wrapper script runs `dart pub get` the first time, and compiles
a snapshot on the first run and whenever the CLI's or the app's sources change: about a
second then, about 0.1 s every run after. Put it on your `PATH` with a symlink if you like.
`dart run bin/fazoura.dart` works too, and compiles every time.

It talks to `http://localhost:4000` — the local stack, or `mix phx.server` — unless told
otherwise:

```bash
fazoura --server https://party.example.com rooms
export FAZOURA_SERVER=http://localhost:41593
```

Global options go before the command: `--server`, `--json`, `--owner-key`.

## Playing

```bash
fazoura rooms                                   # public rooms anyone can join
fazoura host --quiz world-capitals              # open a room and run it by hand
fazoura join K7QX2M --name Sam                  # join it and type answers
```

A **host** types commands: `start`, `end` / `next`, `pause`, `resume`, `right Sam`,
`wrong Sam`, `remove Sam`, `report Sam hate <note>`, `select <quiz>...`,
`set questions=10 time=20 scoring=on difficulties=easy,hard`, `listed on|off`, `size 12`,
`code K7QX-2MPA-9RTE`, `transfer Sam`, `rematch`, `close`, `players`, `state`, and `a <answer>` to
answer when playing along (`--name`). A **player** types an answer and presses enter;
commands start with `/` (`/players`, `/state`, `/report Sam spam`, `/leave`). Reporting
a player is for rooms on the server.

A quiz is anything the app can host: an id or slug from the library, or a quiz kept locally —
a `.fazoura`, a folder, or a `.json` document — which is sent inline the way the app sends one
kept on the device. `--quiz` repeats, up to ten, and they are drawn from as one pool.

```bash
fazoura host --name Hana --quiz tech-acronyms --quiz ./film-night --questions 15 --time 20
fazoura host --listed --quiz world-capitals     # on the public list: library quizzes only
fazoura host --lan --quiz ./film-night          # hosted by this process, for the local network
fazoura host --room-size 8 --quiz world-capitals               # a smaller room
fazoura host --size-code K7QX-2MPA-9RTE --quiz world-capitals  # a bigger one, with an admin's code
fazoura join K7QX2M --lan 192.168.1.20:4040
```

### Unattended

`host --auto` starts once `--start-when` players are in, keeps answers and standings up for
`--pace` seconds, moves on, plays `--games` games (rematching between them) and closes the
room. A player becomes a **bot** with any answering option, or `--count` above 1:

```bash
fazoura host --auto --quiz world-capitals --questions 5 --start-when 6 &
fazoura join K7QX2M --count 3 --name "Ace {n}" --answers-from world-capitals --delay 0.5-2
fazoura join K7QX2M --count 3 --name "Guess {n}" --answers-from world-capitals \
    --accuracy 0.3 --skip 0.2
```

- `--answers-from <quiz>` — the quizzes being played, whose accepted answers the bot may use.
  A player never sees an answer before a question ends, so a bot has to be *told* — from the
  library's full download, or a local file.
- `--accuracy` — chance of the right answer when it is known; otherwise it answers wrong on
  purpose (`not Paris`). `--skip` — chance of letting a question go by. `--answer TEXT` —
  what to say when nothing is known.
- `--delay 1-4` — seconds before answering, random in the range, always in before the
  deadline. The timing is the app's own (`LockInTimer`): when the host ends a question early
  the deadline moves in, and a pending answer moves with it, exactly as a typed answer does
  on a phone.
- `--count N` — N players on N sockets in one process; `{n}` in `--name` is replaced by the
  number. Several processes fill a room just as well, and are how several hosts run at once.
- Bots leave when the game ends; `--stay` keeps them for a rematch. A host playing along with
  `--auto` answers with the same options.

### For scripts

`--json` prints one JSON object per line on stdout: `room` (code, host token), `joined`,
`state` (the full `RoomState` a seat received, PROTOCOL.md §5.1), `submitted`, `skipped`,
`refused` (an intent the server turned down, with its code), `closed`, and `error`.

```bash
fazoura --json host --auto --quiz tech-acronyms > host.jsonl &
code=$(until grep -m1 -o '"room_code":"[A-Z0-9]*"' host.jsonl; do sleep 0.2; done | cut -d'"' -f4)
fazoura --json join "$code" --count 5 --answers-from tech-acronyms > bots.jsonl
```

Exit codes: `0` done, `1` the server or the input said no, `64` the command was wrong.

## Quizzes

```bash
fazoura quiz list --search capitals             # the public library
fazoura quiz show world-capitals                # as anybody sees it
fazoura quiz download world-capitals -o q.json  # the whole thing, answers included
fazoura quiz archive world-capitals             # as a .fazoura

fazoura quiz init film-night --title "Film Night"   # start a folder from a template
fazoura quiz inspect film-night                 # check it the way the server would
fazoura quiz pack film-night                    # → film-night.fazoura
fazoura quiz inspect film-night.fazoura --extract out/   # and back again

fazoura quiz report <quiz id> --reason spam --note "…"
fazoura quiz submissions                        # the server's side of what was sent from here
```

### This machine's quizzes

The app keeps "My quizzes" on the device and publishes from there; the CLI does the same,
through the app's own `QuizLibrary` and `LocalQuizStore` — a sembast file,
`~/.config/fazoura/library.db` — so publishing from here runs the app's publishing code.

```bash
fazoura quiz import film-night                  # saved here, private
fazoura quiz publish "film night"               # sent for review
fazoura quiz mine                               # asks what became of it, as the app does
fazoura quiz import film-night --into "film night"   # an edit: republishing goes through review
fazoura quiz unpublish "film night"             # withdrawn from review, or taken down
fazoura quiz forget "film night"                # and off this machine
fazoura quiz submit film-night                  # import + publish in one step
fazoura quiz save car-logos                     # "Save offline": photos and all

fazoura host --quiz @film-night                 # host one of them, as the app would
```

A library quiz is named by its title, its slug, or the start of its id (`quiz mine` shows
them). Hosting one goes the way the app sends it: whole, except an offline copy of a
published quiz, which a cloud room is sent by id. Run library commands one at a time —
sembast is not built for two processes writing at once.

`pack` is what `tools/fazoura_pack.py` was: the folder layout, the checks and the package it
writes are those of QUIZ_FORMAT.md §5.3b and QUIZ_AUTHORING.md, photos are named exactly as
the app names them, and packing the same folder twice gives the same bytes. Every photo is
prepared by the app's own `preparePhoto` — at most 1280 px, metadata stripped, clear
backgrounds kept as PNG — so a packed quiz is the size the app would have made it.

Publishing is done as a **publisher key**, like a device: the CLI keeps one per machine in
`~/.config/fazoura/owner_key` (`$FAZOURA_CONFIG_DIR` or `$XDG_CONFIG_HOME` to move it), shared
by every instance, so the library and `submissions` find what was published from here.
`--owner-key` or `FAZOURA_OWNER_KEY` act as somebody else.

## Checks

```bash
scripts/ci.sh tools     # format, analyze, test
```

The tests include a whole game — an automatic host and two bots, one always right and one
always wrong — played over real sockets against the app's LAN host in the same process, a bot
answering inside the closing window when the host ends a question, and the whole publishing
flow through the library against a stand-in server. None of them need a real server.

**What the CLI does not cover** is the app's screens — layout, taps, animation, the rules
sheet, error wording — which `flutter test` covers with a fake connection. Everything under
`app/lib/core` it runs as the app runs it.
