# Sahand Info

A personal notes app for iPhone with an AI assistant built into it. Notes, an
ask-your-notes chat, and reminders live side by side, and every answer is traceable
back to the note it came from.

Two engines power the assistant and speak the same JSON protocol, so the UI behaves
identically either way:

- **Offline AI** — a quantized [Qwen2.5-3B](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF)
  GGUF model running fully on-device through
  [swift-llama-cpp](https://github.com/pgorzelany/swift-llama-cpp) (llama.cpp). No network,
  no account, nothing leaves the phone.
- **Online AI** — Gemini (`gemini-3.5-flash-lite`) with your own API key. Required for the
  extra features the small local model can't do reliably: bilingual categories (English +
  Sorani Kurdish), reminder dates, and the note-writing pattern.

Both engines answer with a single JSON object (`reply`, `action`, `target`, `title`,
`content`, `segments`, …) that `Sources/AIShared.swift` defines and parses, so asking can
also *do* things: `create_note`, `update_note`, `delete_note`, `set_category`,
`set_reminder`.

## What's in the app

| Tab | What it does |
| --- | --- |
| **Notes** | Search, category chips, swipe to delete, `+` to add, gear for Settings. Rows show title, preview, category (English and Kurdish), and reminder date. |
| **Ask** | Chat-style Q&A over your notes. Answers arrive either as a written reply with tappable source chips (jump straight to the note, with the supporting line highlighted) or as a clean value you can copy — passwords, prices, phone numbers, dates. Prior turns are sent as context, so "make it 25 instead" works. |
| **Date** | Everything with a reminder, sorted most-urgent → least-urgent with a red→yellow→green gradient, plus filters for date range, done, and not done. |

**Settings** covers answering style, the AI engine and Gemini key, a note-writing pattern
the AI copies when it creates notes, ten gradient themes, and export/import of all notes as
one JSON file.

When the online engine is unavailable (bad key, rate limit, no signal), the app tells you to
flip to Offline AI instead of silently failing — and `QuestionAnswerer` in
`Sources/SahandInfoApp.swift` is a dependency-free keyword/synonym matcher used for the
Jump & Highlight mode and as a note-ranking step.

## Requirements

- macOS with **Xcode 16.3 or newer** (`swift-llama-cpp` needs the Swift 6.1 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- iOS 17+ device or simulator. The offline model wants a phone with ≥6 GB RAM
  (iPhone 15 Pro / 16 or newer); skip the model on anything older and use Online AI.
- ~200 MB of the llama.cpp XCFramework is downloaded by Swift Package Manager on the
  first build, and the model file itself is about 2 GB.

## Getting started

```sh
brew install xcodegen

# Optional — only needed for Offline AI. Downloads Resources/model.gguf (~2 GB, one time).
./scripts/fetch-model.sh

xcodegen generate          # writes SahandInfo.xcodeproj (never committed)
open SahandInfo.xcodeproj  # then run on a device or the simulator
```

There is no `Podfile`/`Package.swift`: the Xcode project is generated from `project.yml`, so
**edit `project.yml` (and `Sources/Info.plist`) rather than the generated project**, and
re-run `xcodegen generate` after changing either.

The app runs fine without `Resources/model.gguf` — *Online AI (Gemini)* only. Add a key under
Settings → AI Engine, and Offline AI will simply report that the model file is missing from
the bundle.

### Building an IPA

- **From CI**: Actions → **Build IPA** → *Run workflow*. Pick the branch, then:
  - *offline_model* = **off** → small, fast build, Online AI (Gemini) only.
  - *offline_model* = **on** (default) → bundles the ~2 GB model. Set *model_url* to
    something smaller if you're testing on a phone, e.g.
    `https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf`
    (~1.1 GB) — anything ending in `.gguf` works, the script saves it as `model.gguf`.
  The run uploads an unsigned `SahandInfo.ipa` artifact.
- **Locally**: `./scripts/build-ipa.sh` (or `WITH_MODEL=0 ./scripts/build-ipa.sh`), which runs
  the exact same steps as the workflow.

### Testing on a real device

The download from Actions is `SahandInfo-ipa.zip`; unzip it to get `SahandInfo.ipa`
(that zip wrapper trips people up — the `.ipa` is *inside* it).

- **LiveContainer** is the easy path for testing, since its whole trick is running IPAs
  without a normal signature: with JIT available codesign is bypassed entirely, and in
  JIT-less mode LiveContainer re-signs the app with the SideStore/AltStore certificate it
  already has. So this unsigned artifact is installable as-is — no re-signing step needed.
  Requires LiveContainer installed via SideStore 0.6.0+ / AltStore 2.0+ (or TrollStore).
- **Everything the app does still works in a container** except things that need a real
  app install: no home-screen icon, no notification delivery, haptics are unreliable.
- The offline model is the risky part in a container: LiveContainer runs the app inside its
  own process, so llama.cpp's ~1.5–2 GB resident footprint competes with the container's
  memory limit and jetsam will kill it on 4 GB devices. Use the 1.5B URL above, or install
  a standalone copy via TrollStore/Sideloadly for serious offline testing.
- **Sideloadly / AltStore installs**: those check `UIRequiredDeviceCapabilities`, which is why
  `Sources/Info.plist` now asks for `arm64` rather than the legacy `armv7` (an `armv7`
  requirement makes current iPhones refuse the install). LiveContainer ignores that key.

The IPA is **unsigned** — there is no certificate or provisioning profile in this repo. Install
it by letting AltStore or Sideloadly re-sign it with your own Apple ID, or set a real
`DEVELOPMENT_TEAM` / `CODE_SIGN_IDENTITY` in `project.yml` and archive from Xcode.

## Layout

```
project.yml                     XcodeGen spec — the only definition of the target/scheme
Sources/
  SahandInfoApp.swift           UI, stores (notes, settings), the offline matcher, themes
  AIShared.swift                The prompt + JSON protocol both engines share
  LocalAI.swift                 On-device inference via SwiftLlama
  OnlineAI.swift                Gemini REST calls, retries, category suggestions
  Info.plist                    Hand-maintained (GENERATE_INFOPLIST_FILE is off)
Resources/
  Assets.xcassets               App icon (single-size 1024×1024)
  PrivacyInfo.xcprivacy         Apple privacy manifest
  model.gguf                    The offline model — downloaded, NOT in git (see Resources/README.md)
scripts/
  fetch-model.sh                Get the GGUF model into Resources/
  build-ipa.sh                  generate → build → package .ipa, same as CI
.github/workflows/
  ci.yml                        On every push/PR: validate plists, icon, scripts, then compile
  build.yml                     Manual: full release build + unsigned IPA artifact
```

## Data, privacy, and backups

- Notes live only on the device, in `UserDefaults` as JSON under `sahand_info_notes_v1`
  (settings: `sahand_info_answer_mode_v1`, `sahand_info_use_online_ai_v1`,
  `sahand_info_deepseek_api_key_v1`, `sahand_info_note_pattern_v1`, `sahand_info_theme_v1`).
- **Backups are yours to keep**: Settings → *Export All Notes* writes
  `SahandInfoNotes-YYYY-MM-DD.json` (a pretty-printed array of note objects) that you can
  AirDrop or stash in iCloud Drive. *Import* adds new notes and updates ones with matching ids;
  it never deletes. Old backups from before categories/reminders existed still import.
- The only network call in the app is the Gemini request, over HTTPS (App Transport Security
  allows no arbitrary loads). Nothing is tracked or collected — see `Resources/PrivacyInfo.xcprivacy`.
- Heads-up before using this for sensitive notes: the Gemini API key is stored in plain
  `UserDefaults` (not the keychain), and anything you ask the online model sends your matched
  notes to Google. Use a dedicated key with its own quota, and prefer Offline AI for
  passwords and other secrets.

## Known limitations

- Reminders are dates plus a completion flag — the app does not schedule local notifications.
- The API key is not in the Keychain, and there are no unit tests yet (`AIProtocol.parse` and
  `Note`'s decoder would be the first things worth covering).
- The whole UI sits in one file; splitting `Sources/SahandInfoApp.swift` along its `// MARK:`
  sections is the obvious refactor.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `xcodegen generate` errors with *"Source path ... doesn't exist"* | `Sources/` or `Resources/` is missing. `Resources/` must exist even without a model: `mkdir -p Resources && touch Resources/.keep`. |
| Offline AI answers *"Model file missing from app bundle."* | `Resources/model.gguf` was absent when the app was built → `./scripts/fetch-model.sh`, then rebuild (the copy-resources step happens at build time). |
| First build stalls or fails on `llama` | The package downloads a ~200 MB XCFramework from the llama.cpp releases. Retry, or clear *Package Cache* in Xcode → Settings → Locations. |
| Offline model output isn't valid JSON | Expected with a 3B model now and then — the parser falls back to showing the raw text as a plain reply. Switch to Online AI for actions like categories and reminders. |
| Offline generation is slow or the app is killed mid-answer | The model is memory-hungry. Lower `maxTokenCount` in `Sources/LocalAI.swift`, use a smaller quantization (`MODEL_URL=... ./scripts/fetch-model.sh`), or use Online AI. |
| Answers look wrong after editing notes | The prompt only carries notes that matched the question; if nothing matches it says so. Try wording closer to the note text. |
| `xcodebuild` says the scheme isn't defined | Re-run `xcodegen generate` — the shared `SahandInfo` scheme is declared under `schemes:` in `project.yml`. |

## License

No license file has been added, so all rights are reserved by the author. Add a `LICENSE` if
you want this public.
