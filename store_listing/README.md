# Google Play store listing

The text and artwork for the Play Console's **Main store listing**. Paste each block into the field of
the same name. Play counts characters, not bytes, and rejects anything over its limit.

| Field | Limit | File |
|---|---|---|
| App name | 30 | below |
| Short description | 80 | below |
| Full description | 4000 | below |
| Feature graphic | 1024 × 500 PNG/JPEG, ≤ 15 MB | [`feature_graphic.png`](feature_graphic.png), from [`feature_graphic.svg`](feature_graphic.svg) |
| Phone screenshots | 4–8, 9:16 or 16:9, 320–3840 px a side, ≤ 8 MB each | [`screenshots/1-home.png`](screenshots/1-home.png) … [`8-finished.png`](screenshots/8-finished.png), in upload order |
| App icon | 512 × 512 PNG | [`design/icons/play-store-512.png`](../design/icons/play-store-512.png) (generated, see `design/icons/README.md`) |

`store_listing/check.sh` holds all of it to Play's limits. Every image is generated, so never
edit a PNG by hand.

- **Feature graphic:** edit `feature_graphic.svg`, then run `store_listing/render.sh`.
- **Phone screenshots** are the app's real screens, rendered by a widget test with a made-up
  party in [`app/tool/store_screenshots/screenshots_test.dart`](../app/tool/store_screenshots/screenshots_test.dart),
  then framed with a caption from [`screenshots/captions.txt`](screenshots/captions.txt) by
  [`screenshots/frame.svg`](screenshots/frame.svg):

  ```bash
  cd app && flutter test tool/store_screenshots/screenshots_test.dart
  store_listing/render.sh
  ```

  The test writes the bare screens to `screenshots/raw/`, which is not committed. The flag in the
  photo question is drawn by the test, so the listing shows nobody's artwork or trademark — keep
  it that way if a screenshot gains a photo.

## App name

<!-- listing:name -->
Fazoura Party
<!-- /listing:name -->

## Short description

<!-- listing:short -->
Party trivia on everyone's phone. Share a code, type your answers, shout a lot.
<!-- /listing:short -->

## Full description

<!-- listing:full -->
Fazoura means "a riddle". Fazoura Party is trivia for a room full of people with their own phones.

One person hosts. Everyone else joins with a six-character room code, from the app or a web browser, and the questions appear on every screen at once. The host can play along too, so nobody sees the right answer or anyone else's guess until the question closes.

TYPE THE ANSWER
No multiple choice to guess from. Players type what they think it is, and the answer is matched ignoring case, accents and extra spaces. When "Da Vinci" and "Leonardo da Vinci" should both count, the host can override the marking once the question is over, and the scores update straight away.

RISK IT OR LET IT GO
Turn on difficulty scoring and every question is worth what its difficulty says:
• Easy: +10 right, −15 wrong
• Medium: +25 right, −10 wrong
• Hard: +50 right, −5 wrong
Getting an easy one wrong costs the most, and letting any question go by costs 10, so staying quiet is never the safe way out of a hard one. Leave it off and every question is a flat +10 or −10.

YOUR QUIZZES, OR EVERYONE'S
• Browse a public library of quizzes, searchable by tag.
• Write your own in the app, with photos on any question.
• Keep a quiz private on your device, or submit it to the public library. Every submission is read by a person before it goes live.
• Mix up to ten quizzes in one round; the questions are drawn from all of them.
• Choose how many questions to play and how long each one lasts, from 10 seconds to 2 minutes.
• Save a public quiz to your phone to host it offline later.

NO INTERNET? NO PROBLEM
On Android, host a room on your own Wi-Fi. Guests on the same network join with the same code, and the whole game runs on the host's phone.

PUBLIC ROOMS
Open your room to anyone, or join one that is already playing. Public rooms only play quizzes from the reviewed library, the host can remove any player, and anyone can report a player or a quiz from inside the game.

MADE FOR A PARTY
• Up to 32 players in a room.
• Live scores and a leaderboard after every question.
• Rematch in the same room with the same players.
• A phone that locks mid-question gets a moment to come back before it counts as gone.
• Quizzes, names and answers in Arabic or English, each laid out in its own direction.

PRIVATE BY DESIGN
No accounts, no ads, no analytics and no tracking. You never give us a name, an email or a phone number. A game lives in the server's memory while it is played and is gone when the room closes.

Fazoura Party is for ages 13 and over. Please read the community rules before hosting or joining a public room.
<!-- /listing:full -->
