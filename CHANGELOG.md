# Changelog

## 1.0.2

### Fixed

- **Platform selection always shown** — platform (Android / iOS / Android + iOS)
  is now asked on every run and never auto-selected from saved config; this was
  silently defaulting to the previously saved platform, which caused unintended
  builds
- **Google Drive upload progress now visible** — switched rclone stats from
  `--stats-one-line` (suppressed when stderr is not a TTY) to
  `--use-json-log --stats 1s` (JSON lines written to stderr unconditionally);
  live progress bar with %, MB transferred, speed, and ETA now renders reliably

### Changed

- Platform is no longer saved to the project config file; it is always a
  build-time prompt

---

## 1.0.1

### Added

- **Environment selection** — choose DEV, UAT, or PROD before every Drive upload;
  selection is mandatory and never persisted so each build is intentional
- **New Google Drive hierarchy** — uploads now land at
  `<root>/<AppName>/<year>/<month>/<ENV>/<file>.apk` instead of the flat
  `<root>/<year>/<month>/<file>.apk` structure; supports multiple apps, multiple
  environments, and long-term archive navigation
- **Smart folder reuse** — before creating any folder at any hierarchy level,
  existing folders are listed and matched case-insensitively (`Ruloans` reuses
  `ruloans`); prevents duplicate folders across runs
- **Destination preview** — tree view of the full upload path is displayed
  before the upload starts so the user can verify the destination
- **Real-time upload progress** — rclone stats parsed in real time and rendered
  as `[████░░░] 64%  42.1 MB / 65.4 MB  4.2 MB/s  ETA: 6s`; updates every
  second throughout the upload
- **`flutter_release_manager config`** — interactive menu for editing project
  directory, app name, Google Drive account, Drive root folder, Diawi token,
  upload preferences; reset option included; saves immediately
- **Startup configuration screen** — on subsequent runs shows current project,
  Drive folder, account status, and Diawi status; one-key navigation
  (`[Enter]` continue, `[c]` config, `[q]` quit)
- **Persistent upload preferences** — `autoUploadDrive` and `autoUploadDiawi`
  saved to machine config; tool never asks for information it already knows
- **macOS Gatekeeper handling** — one-time security notice shown before first
  build; Gatekeeper error patterns detected in build output with actionable
  recovery steps (System Settings path + xattr command)
- **`flutter_release_manager doctor`** — now includes `dart` executable check
  and macOS Gatekeeper advisory section that detects quarantined binaries and
  prints exact `xattr` clear commands
- **`--environment` / `-e` flag** — CI/non-interactive mode: pass
  `--environment UAT` to skip the interactive prompt

### Changed

- **Drive upload path** — new hierarchy: Root Folder → App Name → Year →
  Month → Environment → APK file
- **APK filename** — now includes environment:
  `AppName_ENV_YYYY_MM_DD_HHmm.apk` (e.g. `Ruloans_UAT_2026_06_18_1326.apk`)
- **Build summary** — shows Environment, Google Account, Drive Folder, and full
  Destination path before every build
- **Config menu option 4** — renamed to "Google Drive Root Folder"
- **Onboarding** — macOS users see a one-time security notice with clear
  instructions for approving Dart, Flutter, and rclone on first use

### Fixed

- Duplicate Drive folders from case mismatch (e.g. `Ruloans` vs `ruloans`)
- Upload preferences not being remembered between runs
- Saved project directory no longer validated on startup — warns and asks for
  replacement if the directory has been moved or deleted
- Progress display cleared cleanly between upload retries

---

## 1.0.0

Initial release of `flutter_release_manager`.

### Features

- Android APK build automation (`flutter build apk --split-per-abi`)
- iOS IPA build automation via `xcodebuild` archive and export
- Google Drive upload via rclone — no Google Cloud Console, no OAuth client IDs
- Diawi upload for iOS tester distribution
- `flutter_release_manager init` — installs rclone, signs into Google Drive,
  picks destination folder, saves Diawi token
- `flutter_release_manager doctor` — pre-flight health check
- Automatic rclone installation (macOS: Homebrew, Linux: apt-get)
- Upload retry with exponential back-off (3 attempts, 3s/6s delays)
- 30-minute upload timeout; 5-minute OAuth timeout
- Non-interactive rclone authentication — stdin closed immediately, interactive
  prompt detection kills the process rather than hanging
- CI/non-interactive mode via flags (`--platform`, `--app-dir`, `--app-name`,
  `--upload-drive`, `--team-id`, `--skip-build`)
- Automatic migration from `flutter_build_release` — machine config, project
  config, and rclone remote token all migrated on first run

---

### Migrating from `flutter_build_release`

```bash
# Install the new package
dart pub global activate flutter_release_manager

# Run init (existing Google Drive access is preserved)
flutter_release_manager init

# Remove the old package
dart pub global deactivate flutter_build_release
```

All saved configuration, Google Drive tokens, and project settings migrate
silently on first run. No re-authentication required.
