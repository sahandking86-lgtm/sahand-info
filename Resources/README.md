# Resources

Bundled app resources. The whole folder is handed to the app target by `project.yml`
(`sources: - path: Resources`), so **this folder must exist** — XcodeGen fails with
*"Source path doesn't exist"* if it is missing. Only `README.md` is excluded from the
copy-into-bundle step; everything else ships inside the app.

## What lives here

| Path | Tracked in git | Purpose |
| --- | --- | --- |
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | yes | The iPhone app icon (single-size 1024×1024, no alpha). Wired up with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. |
| `PrivacyInfo.xcprivacy` | yes | Apple privacy manifest. Declares that nothing is tracked or collected, and gives the required reason (`CA92.1`) for the `UserDefaults` access used by `NotesStore`/`SettingsStore`. |
| `model.gguf` | **no** (`.gitignore`) | The offline AI model that `Sources/LocalAI.swift` looks up at runtime with `Bundle.main.url(forResource: "model", withExtension: "gguf")`. |

## The offline model (`model.gguf`)

It is deliberately not in git — it is roughly 2 GB. Fetch it with:

```sh
./scripts/fetch-model.sh
```

Notes:

- The file must be named exactly `model.gguf`; that is the resource name the code looks for.
- Download it **before** the first build so Xcode adds it to *Copy Bundle Resources*.
- The default is `Qwen2.5-3B-Instruct-q4_k_m.gguf`, a good size/quality trade-off for
  recent iPhones (it wants a device with ≥6 GB RAM). Any instruct-tuned chat-template GGUF works;
  override with `MODEL_URL=... ./scripts/fetch-model.sh`.
- Skip it entirely if you only use **Online AI (Gemini)** — the app builds and runs without it,
  and Offline AI simply answers with *"Model file missing from app bundle."*
- Do not commit a model to this repo. If you really want it versioned, use
  `git lfs track "*.gguf"` and update CI to `lfs: true` on `actions/checkout`.
