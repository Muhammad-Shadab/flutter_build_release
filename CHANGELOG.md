# Changelog

## 1.0.0

Initial release of `flutter_release_manager` — a brand-new package that
supersedes the retired `flutter_build_release` package.

### Features

- **Android APK build automation** — runs `flutter build apk --split-per-abi`,
  selects the `arm64-v8a` artifact automatically (falls back to `armeabi-v7a`)
- **iOS IPA build automation** — archives and exports via `xcodebuild`; no
  manual Xcode interaction required
- **Google Drive upload** — powered by rclone; no Google Cloud Console, no
  OAuth client IDs, no API keys; one browser sign-in during init and never again
- **Diawi upload** — iOS IPA distributed to testers via a shareable install
  link; Diawi token stored securely in machine config
- **Automated rclone authentication** — `flutter_release_manager init` installs
  rclone (macOS via Homebrew, Linux via apt-get), opens a browser for Google
  OAuth, and embeds the token in the rclone remote non-interactively; no
  interactive prompts, no deadlocks
- **Upload retry logic** — 3 attempts with exponential back-off (3s, 6s) for
  both Google Drive and Diawi uploads; 30-minute upload timeout
- **Live upload progress** — Google Drive upload shows percentage, bytes
  transferred, speed, and ETA via rclone's `--progress` flag; Diawi upload
  shows a byte-level progress bar updated every chunk
- **`flutter_release_manager doctor`** — pre-flight health check: verifies
  flutter, rclone, Google Drive remote, Drive connection, Drive folder, and
  Diawi token
- **`flutter_release_manager init`** — one-time setup wizard; installs rclone,
  signs into Google Drive, picks destination folder, saves Diawi token
- **`flutter_release_manager config`** — interactive configuration editor with
  menu-driven editing of project directory, app name, Google Drive account,
  Drive folder, Diawi token, and upload preferences; reset option included
- **Persistent configuration** — project directory, app name, and upload
  preferences (auto-upload / skip / ask) are saved to machine config; the tool
  never asks for information it already knows
- **Startup summary screen** — on subsequent runs shows current project, Drive
  folder, account status, and Diawi status with one-key navigation (`Enter` /
  `c` / `q`)
- **Upload preference memory** — `autoUploadDrive` and `autoUploadDiawi`
  settings suppress the upload prompt on every run; editable via
  `flutter_release_manager config`
- **Project directory validation** — if the saved project directory is deleted,
  the tool warns and asks for a replacement; no silent failures
- **Detailed build summary** — shows project name, directory, platform, Drive
  folder, account status, and Diawi status before every build
- **CI / non-interactive mode** — all settings overridable via flags
  (`--platform`, `--app-dir`, `--app-name`, `--upload-drive`, `--team-id`,
  `--diawi-token`, `--skip-build`)
- **Upload-only mode** — `--skip-build` / `--upload-only` re-uploads the last
  built artifact without recompiling; useful after a failed upload
- **Automatic configuration migration** from `flutter_build_release` — machine
  config, project config file, and rclone remote token are all migrated on
  first run; no re-authentication required
- **Deadlock prevention** — stdin closed immediately on all rclone subprocesses;
  interactive-prompt pattern detection kills the process rather than hanging

---

### Migrating from `flutter_build_release`

1. Activate the new package:
   ```bash
   dart pub global activate flutter_release_manager
   ```
2. Run init (your existing Google Drive access is preserved automatically):
   ```bash
   flutter_release_manager init
   ```
3. Deactivate the old package:
   ```bash
   dart pub global deactivate flutter_build_release
   ```
4. Update any CI scripts: replace `flutter_build_release` with
   `flutter_release_manager`.

All saved configuration, Google Drive tokens, and project settings are migrated
silently on first run. No data loss. No re-authentication.
