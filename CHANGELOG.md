# Changelog

## 3.0.0

### Changed

- **Package renamed**: `flutter_build_release` → `flutter_release_manager`
- **Architecture**: replaced Google Drive REST API (`googleapis`) with rclone — no Google Cloud
  Console, no OAuth client IDs, no API keys required
- Google Drive authentication is now fully browser-based: `flutter_release_manager init` opens
  a browser once, stores the token securely, and never prompts again
- Machine config moved to `~/.config/flutter_release_manager/config.json`
  (Windows: `%APPDATA%\flutter_release_manager\config.json`)
- Project config renamed to `.flutter_release_manager_config.json`
- rclone remote name changed to `flutter_release_manager`
- New command: `flutter_release_manager init` — one-time setup wizard; installs rclone, signs
  into Google Drive, picks destination folder, optionally saves Diawi token
- New command: `flutter_release_manager doctor` — prerequisite health check with fix hints
- Removed `--drive-folder-id` and `--flavour` flags (Drive folder is now selected during init)
- Removed `--rclone-remote` flag (remote is created and managed automatically)
- rclone auth is 100% non-interactive: `rclone config reconnect` is never called; OAuth
  token is obtained via `rclone authorize` (browser-only) and embedded at remote creation time

### Added

- `flutter_release_manager init` setup wizard
- `flutter_release_manager doctor` health check
- Automatic rclone installation on macOS (Homebrew) and Linux (apt-get)
- Automatic migration of all configuration from `flutter_build_release`:
  - Machine config (`~/.config/flutter_build_release/`) copied on first run
  - Project config (`.flutter_build_release_config.json`) copied on first run
  - rclone remote `flutter_build_release` migrated without re-authentication
- Deadlock prevention: stdin closed immediately on all rclone subprocesses; interactive
  prompt detection kills the process rather than hanging indefinitely
- Upload retry: 3 attempts with exponential back-off (3 s, 6 s)
- 30-minute upload timeout; 5-minute OAuth timeout

### Removed

- `googleapis` and `googleapis_auth` dependencies
- `DriveUploader`, `DriveAuthenticator`, `CredentialStore` classes
- All Google Drive REST API code

### Migration Guide

1. **Install the new package:**
   ```bash
   dart pub global activate flutter_release_manager
   ```

2. **Run init** (your existing Google Drive access is preserved automatically):
   ```bash
   flutter_release_manager init
   ```
   On first run, your old config, project settings, and rclone remote are migrated silently.
   No re-authentication is required.

3. **Remove the old package:**
   ```bash
   dart pub global deactivate flutter_build_release
   ```

4. **Update CI scripts**: replace `flutter_build_release` with `flutter_release_manager`.

---

## 2.0.0

**Breaking change — rclone is no longer required.**

- Replace rclone with native Google Drive REST API (`googleapis` + `googleapis_auth`)
- First-run OAuth flow: browser opens automatically, refresh token saved to
  `~/.config/flutter_build_release/credentials.json`
- Subsequent runs load stored token and refresh it silently — no prompts for credentials
- Credentials (Drive refresh token, Diawi API token) moved to machine-level store;
  project config never contains secrets
- `ConfigStore.save()` now auto-appends `.flutter_build_release_config.json` to `.gitignore`
- v1.x `diawiToken` in project config is migrated to `CredentialStore` on first run
- Add `--skip-build` / `--upload-only` flag: upload an already-built artifact without recompiling
- `runLive()` gains a 20-minute timeout; process is killed on expiry
- Drive upload retries up to 3× with exponential back-off (3s, 6s)
- Diawi upload retries up to 3× with exponential back-off before polling
- Remove `--rclone-remote` flag (no longer relevant)
- Drive folder URL accepted as input; folder ID extracted automatically
- Pre-flight validation now verifies Drive folder accessibility via the API before the build starts
- Prefer arm64-v8a APK; emit explicit warning when falling back to armeabi-v7a

## 1.0.3

- Fix: resolve correct package source directory when installing from pub.dev

## 1.0.2

- Auto-detect Flutter project directory when run from inside the project
- Auto-detect app name from `pubspec.yaml` (converted to PascalCase)
- Persist answers to `.flutter_build_release_config.json` — no retyping on subsequent runs
- Pre-flight checks: verify `flutter`, `rclone`, and `xcodebuild` are available before building
- Show a pre-build summary and require confirmation before starting
- Show all testing URLs together in a final summary after build completes
- Fix: CLI flags `--rclone-remote`, `--scheme`, `--export-method` now correctly override saved config
- Fix: error messages now always show both example values and the fix instruction
- Fix: invalid menu choices now retry instead of exiting
- Fix: upload `arm64-v8a` APK (modern devices) with fallback to `armeabi-v7a`
- Fix: auto-discover `.xcworkspace` file in `ios/` instead of hardcoding `Runner.xcworkspace`
- Fix: flavour menu uses consistent `1/2/3` numbering to match platform menu
- Warn when Diawi token is saved to disk for the first time

## 1.0.1

- Remove sensitive example credentials from documentation

## 1.0.0

- Initial release
- Build Flutter APK with `--split-per-abi`
- Build iOS IPA via xcodebuild archive + export
- Upload APK to Google Drive using rclone with `dev/prod/uat` folder structure
- Upload IPA to Diawi with polling until processed
- Auto-copy Diawi link to clipboard on macOS
