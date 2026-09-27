# Sahand Info

A personal notes app for iPhone with an AI assistant built into it. Notes, an
ask-your-notes chat, and reminders live side by side, and every answer is traceable back to
the note it came from.

The assistant answers with a single JSON object (`reply`, `action`, `targets`, `scope`, `title`,
`content`, `mode`, `when`, `note_id`, `segments`, …) that `Sources/AIShared.swift` defines and
`Sources/AIActions.swift` applies, so asking can also *do* things: `create_note`, `update_note`
(replace a phrase, append to the note, or rewrite the whole body), `delete_note` (one or many),
`set_reminder`, `clear_reminder`, `complete_reminder`, `set_category`, and `find_note` — which
opens the note and marks the line the answer came from. Every write goes through a confirmation the
app builds itself (`AIActionPreview`), so a model that invents a note title gets "I couldn't find
that note" rather than an edit to whichever note happened to match loosely; a delete of more than one
note lists the titles and counts them before anything is removed.

There is one AI assistant: **Groq**, called over WiFi from `Sources/OnlineAI.swift`, with your own
free API key and no card. The default model is `openai/gpt-oss-120b`, a 117-billion-parameter
reasoning model; `openai/gpt-oss-20b`, `llama-3.3-70b-versatile`, `llama-3.1-8b-instant` and
`qwen/qwen3.8-27b` are selectable in Settings when a free tier moves models around. The list is copied
from the provider's supported-models page rather than from memory: two names that were valid last week
are no longer offered at all, and a dropped name would otherwise be a 404 nobody can explain. Why only one, and why not the one this app used first, is in
[Why there is only one assistant](#why-there-is-only-one-assistant). Alongside the assistant,
`QuestionAnswerer` in
`Sources/SahandInfoApp.swift` is a dependency-free keyword/synonym/value matcher, used for
**Jump & Highlight** mode: that mode needs no key and no network at all, so the app is
still useful with no connectivity.

## What's in the app

| Tab | What it does |
| --- | --- |
| **Notes** | Search, category chips, swipe to delete, `+` to add, gear for Settings. Rows show title, preview, category (English and Kurdish), and reminder date. Tapping the bell on a row ticks that reminder off; a long press offers Edit, the reminder, the category and delete. A new note stays visible while you type, so it can't be written out from under you. |
| **Ask** | Chat-style Q&A over your notes. Answers arrive either as a written reply with tappable source chips (jump straight to the note, with the supporting line highlighted) or as a clean value you can copy — passwords, prices, phone numbers, dates. Prior turns are sent as context, so "make it 25 instead" works. It also *does* things: create, change, move, append, delete (one or many), file or clear a reminder, tick one off, set or clear a category, and find or open a note. Anything that changes or deletes a note waits for a **Confirm / Keep it** card you can answer by tapping or by typing "yes" / "no", and the message itself carries an **Undo** chip while that change is still the most recent one. A ✕ clears the conversation *and* its memory together, and **Stop** abandons a request in flight. |
| **Date** | Everything with a reminder. Each one is coloured by *where it ranks* among what you are waiting on, not by an absolute number of days: the nearest third red, the next third amber, the rest green — nine reminders is 3 / 3 / 3, seven is 3 / 2 / 2, ten is 4 / 3 / 3, and with one or two the nearest simply is the urgent one. Past its date is always red and labelled overdue; finished is grey. The same colours sit on the bell in the Notes list, and no filter changes any of them. Filter by status or date range, tick the circle to finish, swipe to delete, tap the row to open it. |

**Settings** (the gear in the Notes tab) covers answering style, the Groq key and model
(trailing whitespace is stripped on entry, and **Test key** tells you whether it is accepted before you
need it), reminder notifications, a note-writing pattern the AI copies when it creates notes,
ten gradient themes, export/import of all notes as one JSON file, and the version at the bottom.

Backups go to a folder that survives a relaunch, and the file is offered through the share sheet
(AirDrop, Files, iCloud Drive) right after each export. Importing lists what it found and lets you
choose **New notes only** or **Replace everything**; either way it lands as a single undo point,
and a note that is newer on your phone than in the file is never overwritten.

Categories are bilingual — English plus Sorani Kurdish — and are suggested by the AI both
when it writes a note for you and, after a pause in typing, for notes you write yourself.

## Requirements

- macOS with **Xcode 15 or newer** (anything with the iOS 17 SDK). No external packages, so
  nothing to resolve or download at build time.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- An iPhone or simulator on **iOS 17+**.
- A free [Groq API key](https://console.groq.com/keys) for the AI Answer mode — no credit card, and
  far more requests a day than this app can make use of.

## Getting started

```sh
brew install xcodegen
xcodegen generate          # writes SahandInfo.xcodeproj (never committed)
open SahandInfo.xcodeproj  # then run on a device or the simulator
```

There is no `Podfile`/`Package.swift`: the Xcode project is generated from `project.yml`, so
**edit `project.yml` (and `Sources/Info.plist`) rather than the generated project**, and
re-run `xcodegen generate` after changing either.

Without a key the app still works — notes, reminders, search and Jump & Highlight are all local —
but *AI Answer* replies with "Add your Groq API key in Settings first".

### Building an IPA

- **From CI**: Actions → **Build IPA** → *Run workflow* → pick the branch. No options; it
  generates the project, compiles for `iphoneos`, then runs `scripts/check-bundle.py` on the
  bundle **inside the zipped archive** — a red "Validate packaged IPA" step means the artifact
  itself is unusable, a green one means the package is launchable-shaped and any remaining
  problem is on the phone. Uploads an unsigned `SahandInfo.ipa` artifact (a few minutes).
- **Locally**: `./scripts/build-ipa.sh`, which runs the same steps.

The IPA is **unsigned** — there is no certificate or provisioning profile in this repo. Get it
onto a phone by letting AltStore or Sideloadly re-sign it with your Apple ID, or set a real
`DEVELOPMENT_TEAM` / `CODE_SIGN_IDENTITY` in `project.yml` and archive from Xcode.

### Testing on a real device

The download from Actions is `SahandInfo-ipa.zip`; unzip it to get `SahandInfo.ipa` (that zip
wrapper trips people up — the `.ipa` is *inside* it).

**LiveContainer** is the easiest path, since its whole trick is running IPAs without a normal
signature: with JIT available codesign is bypassed entirely, and in JIT-less mode
LiveContainer re-signs the app with the SideStore/AltStore certificate it already holds. So
this unsigned artifact installs as-is. It needs LiveContainer itself installed via
SideStore 0.6.0+ / AltStore 2.0+ (or TrollStore). Everything the app does keeps working inside
the container, except what needs a real install: no home-screen icon, no notification delivery,
and haptics are unreliable.

**Sideloadly / AltStore installs**: those check `UIRequiredDeviceCapabilities`. This file used to
declare the legacy `armv7` only, which is a 32-bit requirement no iPhone since the 5s can satisfy.
The key is now left out and Xcode fills it in as `arm64` on its own — verified against the built
`Info.plist`, not assumed — so nothing needs pinning. LiveContainer ignores the key either way;
main's `armv7` build did install under it, which is worth remembering before blaming a launch
failure on device capabilities.

## Layout

```
project.yml                     XcodeGen spec — the only definition of the target/scheme
Sources/
  SahandInfoApp.swift           Views, stores (notes, settings), themes, the local matcher
  AppCoordinator.swift          Which tab is open, what is selected, pending confirmations, notices
  AIShared.swift                The prompt + JSON protocol the assistant speaks
  AIActions.swift               Applying a parsed action: previews, confirmations, real edits
  OnlineAI.swift                the assistant call, retries, error wording, category suggestions
  ReminderNotifications.swift   Local notifications for dated reminders
  Info.plist                    Hand-maintained, pointed at by INFOPLIST_FILE
Resources/
  Assets.xcassets               App icon (single-size 1024×1024)
  PrivacyInfo.xcprivacy         Apple privacy manifest
scripts/
  check-bundle.py               Asserts a .app is launchable (used by both workflows, runs anywhere)
  test-check-bundle.py          Self-test for the above; CI runs it before it trusts the checker
  build-ipa.sh                  generate → build → verify → package .ipa → verify inside the archive
.github/workflows/
  ci.yml                        On every push/PR: validate plists, icon, scripts, compile, then
                                assert the built .app is launchable
  build.yml                     Manual: release build + unsigned IPA artifact, validated again
                                inside the archive before upload
```

### Why there is only one assistant

The app used to talk to Google's free Gemini tier, and that path has been **deleted** — not hidden
behind a setting, but removed: the request shape, the key field and the stored key itself are gone, so
no code path in this build can send a note there. The reason is the free tier's own terms: prompts and
outputs may be used to improve Google's products, and its terms allow human reviewers to read API input
and output. A notebook is exactly the data you should not accept that for, and it costs nothing to
choose differently — Groq's no-training rule is a clause in its services agreement, its inference
requests are not retained by default, and Zero Data Retention is a toggle in its console. It is also
the stronger model: the reasoning model now used by default scores well above a Flash-Lite class model
on instruction-following and on doing an action correctly, which is precisely what this app asks of it.

The one thing the old provider gave up: a much larger context window and better coverage of languages
like Kurdish, since `gpt-oss` is English-strong. Auto-tagging a note with a Sorani category is the place
you might notice it.

## Data, privacy, and backups

- Notes live only on the device, in `UserDefaults` as JSON under `sahand_info_notes_v1`
  (settings: `sahand_info_answer_mode_v1`, `sahand_info_groq_api_key_v1`, `sahand_info_model_v1`,
  `sahand_info_note_pattern_v1`, `sahand_info_theme_v1`). A key saved by an older build for the
  provider that was removed is **deleted on first launch** — a credential for a service the app can no
  longer reach is risk with no use, so it is not kept "just in case".
- **Backups are yours to keep**: Settings → *Export All Notes* writes
  `SahandInfoNotes-YYYY-MM-DD.json` (a pretty-printed array of note objects) into the app's
  own `Application Support/Backups` — **not** the temporary directory, so the file is still there
  when you go looking for it — and the ten most recent exports are kept. Old backups from before
  categories/reminders existed still import.
- **Nothing is deleted without a way back.** Every edit, including the ones the assistant makes
  and the ones an import performs, pushes a snapshot onto an undo stack owned by the note store,
  so *Undo* works from the Ask tab, the banner, or the Notes tab alike. "Start Over" (Settings →
  Danger zone) also offers it immediately afterwards.
- Reminder dates schedule **local notifications** (`UNCalendarNotificationTrigger`), one per note,
  replaced wholesale whenever a date changes; tapping one opens that note. The badge in Settings
  tells you whether iOS is actually allowed to deliver them.
- The only network call is the request to whichever assistant is selected, over HTTPS (no
  arbitrary loads allowed). Nothing is tracked or collected by the app itself — see
  `Resources/PrivacyInfo.xcprivacy`.
- **What leaves the phone, and to whom.** *AI Answer* sends your notes as prompt context over HTTPS to
  Groq and nowhere else; the app keeps no analytics, no account and no server of its own. Groq's
  no-training rule is a clause in its services agreement, its inference requests are not retained by
  default, and Zero Data Retention is a toggle in its console — see
  [Why there is only one assistant](#why-there-is-only-one-assistant) for what that replaced.
- **One thing is sent without being asked**, and it can be switched off: when you stop typing a note
  that has no category, its title and text go out so a category can be suggested (Settings → AI
  Assistant → *Suggest a category while I type*). Everything else leaves the phone only because you
  asked a question or confirmed a change.
- Before using this for sensitive notes, know too: the API key sits in plain `UserDefaults` (not the
  Keychain). Notes are listed to the model by title, category, reminder date and dates so counts and
  lookups stay honest, but only the notes your wording points at are sent with much of their text — the
  rest arrive as a short excerpt, and a very large collection is shortened for everyone rather than
  refused. The model is told which of those happened. Keep secrets out of the notes
  you ask about, or use **Jump & Highlight**, which answers from the device with no request at all.
- A change the assistant wants to make is sent as a *proposal*; nothing is written to
  your notes until you confirm, and the confirmation runs locally.

## Known limitations

- A question carries at most about 16,000 characters of note text, because the free tier counts 8,000
  tokens *per minute* and a bigger request is refused no matter how long you wait. So the listing gives
  things up in a chosen order: notes that look relevant to your wording are sent in full, the rest as a
  short excerpt; too many for even that, and every note gets a slice sized from what is left; still too
  many, and notes keep only a title and a category. If a collection is large enough that even those will
  not fit, the last few notes are left out and the model is told it is seeing part of the collection —
  never that it is seeing all of it, which is what would make it answer "that is not in your notes"
  about something it was never shown. Counts and searches come from the device, not from the listing.
- *AI Answer* needs a key and connectivity, and there is one provider: if Groq's free tier throttles
  you, waiting is the only lever (the model picker exists so a retired model name is not a dead end).
  Adding a second provider is now a small job — the transport is one path, and only the URL, the
  header and two lines of JSON parsing differ. (The
  on-device llama.cpp engine that used to be here is in git history:
  `git log --oneline -- Sources/LocalAI.swift`.)
- **Notifications only arrive when the app is installed normally.** Installed as a *guest* inside
  LiveContainer, it shares another process, so iOS does not deliver its scheduled notifications —
  the reminder dates, list and undo all still work; only the alert is missing. Same for haptics.
- The bottom **Undo** banner appears only when notes actually went away — a banner for ticking a
  reminder or saving what you typed was noise that taught people to dismiss it without reading. Every
  change is still on the undo stack (up to 15 deep) and the chat keeps its own Undo chip; nothing
  survives a relaunch, and there is no trash.
- There is no multi-select in the Notes list: bulk deletes go through the assistant ("delete all
  my Work notes") or *Start Over* in Settings.
- No unit tests yet; `AIProtocol.parse`, `AIActions` previews and `Note`'s back-compat decoder are
  the first things worth covering.
- `Sources/SahandInfoApp.swift` is still ~3,600 lines; the next split is along its `// MARK:`
  sections (the coordinator, AI, actions and notifications are already separate files).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `xcodegen generate` errors with *"Source path ... doesn't exist"* | `Sources/` or `Resources/` is missing. `Resources/` must exist even when it holds nothing but the icon: `mkdir -p Resources`. |
| *AI Answer* says to add a key | Settings → AI Assistant → paste a key from [console.groq.com/keys](https://console.groq.com/keys), then press **Test key** — it says which part of the problem is yours (key rejected, quota spent, model not offered) instead of blaming the network. |
| Settings says the key looks saved, but every request fails | The key almost certainly has a space or newline in it. Trailing whitespace is stripped on entry now; re-paste it once and the warning goes away. |
| "Groq didn't accept the request (400)" | The response body is quoted in that message — it usually names the exact problem (wrong model name for your key, request too large, malformed content). |
| Answers look wrong after editing notes | Every note is listed but only the ones your wording matches are sent in full. If the answer is in a note the question didn't point at, quote a distinctive phrase from it, or open the note and ask from there. |
| A reminder date passes with no notification | Either notifications are off (Settings → *Notifications allowed?* shows *No — open iOS Settings*), or the app is running as a LiveContainer guest, where iOS doesn't deliver a guest's notifications. |
| The assistant changed or deleted something by mistake | Tap **Undo** in the bar at the bottom — it restores the whole collection as it was, from whichever tab you are in. |
| A note highlighted yellow on open, then the highlight vanished | That's deliberate: it fades out after a couple of seconds rather than staying marked forever. Re-ask or tap the source chip to mark it again. |
| `xcodebuild` says the scheme isn't defined | Re-run `xcodegen generate` — the shared `SahandInfo` scheme is declared under `schemes:` in `project.yml`. |
| No app icon on the home screen | The catalog needs `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (set in `project.yml`) and a 1024×1024 PNG with no alpha; CI checks both. |

## License

No license file has been added, so all rights are reserved by the author. Add a `LICENSE` if
you want this public.
