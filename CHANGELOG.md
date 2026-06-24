# Changelog

## 1.0.10

### Changed

- **README — setup steps table** — added a quick-reference table summarising all 5 `init` wizard steps with expected time.
- **README — troubleshooting quick-reference table** — scannable table of every known problem and its fix, placed at the top of the Troubleshooting section.
- **README — configuration comparison table** — side-by-side table comparing machine config vs project config (location, contents, secrets, gitignore).
- **README — export methods table** — updated to show `ad-hoc` as the correct default with a clear explanation of why `development` IPAs fail to install.
- **README — stale references fixed** — updated all `--export-method development` examples and the project config JSON example to use `ad-hoc`.

---

## 1.0.9

### Fixed

- **iOS IPA install failure** — changed the default `--export-method` from `development` to `ad-hoc`. Development IPAs can only be installed on devices explicitly registered in the development provisioning profile; ad-hoc is the correct method for Diawi distribution and works on any registered device.
- Added `ad-hoc` to the allowed values for `--export-method` and removed the incorrect `release-testing` alias.

---

## 1.0.8

### Changed

- Updated README license section to include author name (MIT License © 2026 Muhammad Shadab)

---

## 1.0.7

### Added

- **`--version` flag** — `flutter_release_manager --version` prints the package
  name and version then exits with code 0
- **`-v` shortcut** — alias for `--version`
- **`version` command** — `flutter_release_manager version` works the same way
- **Full semantic version in banner** — the welcome banner and `--help` output
  now show the full version (`v1.0.7`) instead of the static label `v1`

---

## 1.0.6

### Fixed

- **Duplicate Google OAuth browser** — `flutter_release_manager init` no longer
  opens a second browser tab after a successful Google sign-in. Root cause: the
  previous `rclone config create` call did not pass `--non-interactive`, so
  rclone silently accepted the default (`true`) for its internal
  "Already have a token - refresh?" question and started a second OAuth flow.
  Fixed by driving rclone's config wizard programmatically: the wizard is
  stepped through with `--non-interactive` + `--continue --state … --result …`
  until the state is empty (done), and the `config_refresh_token` question is
  always answered `false` to keep the freshly-obtained token.
- **Remote creation now verified** — after the wizard loop completes,
  `remoteExists()` is called to confirm the remote was written; a clear
  actionable error is shown on failure instead of silently succeeding.
- **Cleaner error messages** — internal rclone exit codes and raw stderr are no
  longer surfaced to users; OAuth failure messages now read
  `Google authorization failed` and
  `Google authorization did not complete successfully`.

### Improved

- Google Drive setup is now guaranteed to require exactly one browser tab.
- `flutter_release_manager init` handles the rclone wizard loop for any number
  of wizard steps (cap 10), future-proofing against rclone adding new questions.

---

## 1.0.5

### Fixed

- **Drive not configured no longer hard-exits** — if rclone is not installed,
  the remote is missing, or no Drive folder is selected, the tool now shows a
  friendly prompt ("Google Drive Not Configured") and offers to continue with a
  local-only build; the user can type `N` to cancel or Enter to proceed without
  uploading
- **App name prompt skipped when already saved** — if a name was saved from a
  previous run (machine config or project config), it is used automatically and
  shown as `✓ App name: Ruloans`; the prompt only appears on first use

### Changed

- **Upload preference auto-saved** — the "Save this preference?" follow-up
  after the Drive / Diawi upload questions has been removed; the answer is saved
  automatically on first response so the question is never asked again
- **Build summary shows Google account email** — the Drive upload section now
  shows the signed-in email address (e.g. `shadab@gmail.com`) instead of the
  generic "Connected" label
- **Clean OAuth output** — raw rclone authorization output is no longer printed
  to the terminal during Google sign-in; only two clean status lines are shown:
  `Opening browser for Google sign-in...` and
  `Waiting for Google authorization (up to 5 minutes)...`
- **Drive URL copied to clipboard** — after a successful Google Drive upload the
  shareable link is automatically copied to the clipboard (macOS: `pbcopy`,
  Windows: `clip`, Linux: `xclip` / `xsel` / `wl-copy`); shown as
  `✓ Link copied to clipboard.`

---

## 1.0.4

### Fixed

- **Google account change now works** — selecting "Change Google account" in
  `config` previously reused the existing token because
  `ensureRemoteAndAuthenticated` exited early when the token was valid; it now
  deletes the rclone remote first so a completely fresh OAuth flow runs every
  time

### Added

- **Account email displayed everywhere** — the connected Google account email
  is shown in the startup configuration screen and in the `config` menu
  (e.g. `shadab@gmail.com` instead of `Connected`); email is fetched via
  Google's userinfo endpoint after OAuth and cached in machine config so
  subsequent starts are instant
- **Disconnect option** — `config → Google Account → Disconnect Google account`
  runs `rclone config delete flutter_release_manager`, clears the cached email,
  and prints a clean confirmation; subsequent `flutter_release_manager` runs
  detect no account and prompt for first-time setup
- **Three-option Google account menu** replaces the previous two-option menu:
  `1) Keep current account  2) Change Google account  3) Disconnect Google account`

---

## 1.0.3

### Changed

- **Diawi upload progress** — complete rewrite of `DiawiUploader`:
  - Timer-driven single-line progress bar updates every second:
    `[████░░░░░░░░░░░░░░░░] 60%  185 MB / 310 MB  5.4 MB/s  ETA: 23s`
  - Per-attempt byte counter isolated from retries; no stale progress on retry
  - Progress bar pins to 100 % briefly then clears cleanly on completion
- **Diawi processing status** — deduplicated live status lines while Diawi
  converts the IPA (`Status: Uploading → Processing → Creating install page →
  Ready`); only emitted when status text changes, no log spam
- **Upload statistics** — completion banner now shows upload time, average
  speed, Diawi processing time, and total time
- **Error handling** — 401 (invalid token), 413 (file too large), timeout,
  and no-internet errors each produce a distinct, actionable message with the
  fix command where applicable

---

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
