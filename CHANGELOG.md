# Changelog

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
