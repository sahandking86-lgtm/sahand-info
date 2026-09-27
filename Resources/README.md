# Resources

Bundled app resources. The whole folder is handed to the app target by `project.yml`
(`sources: - path: Resources`), so **this folder must exist** — XcodeGen fails with
*"Source path doesn't exist"* if it is missing. Only `README.md` is excluded from the
copy-into-bundle step; everything else ships inside the app.

## What lives here

| Path | Tracked in git | Purpose |
| --- | --- | --- |
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | yes | The iPhone app icon (single-size 1024×1024, no alpha). Wired up with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`. |
| `PrivacyInfo.xcprivacy` | yes | Apple privacy manifest. Declares that nothing is tracked or collected, and gives the required reason (`CA92.1`) for the `UserDefaults` access used by `NotesStore`/`SettingsStore`. |

## Adding an image

1. Drop the PNG in `Assets.xcassets/<name>.imageset/` with a `Contents.json` listing it.
2. Use `Image("<name>")` from Swift. Asset catalogs are compiled by `actool`, so a
   malformed `Contents.json` is a build error, not a runtime one.

Nothing here needs to be downloaded before building — the app has no package
dependencies and no bundled model. (The on-device GGUF model that used to live here was
removed; its code is still readable in git history via `git log -- Sources/LocalAI.swift`.)
