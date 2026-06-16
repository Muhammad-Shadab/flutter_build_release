# Changelog

## 1.0.1

- Remove sensitive example credentials from documentation

## 1.0.0

- Initial release
- Build Flutter APK with `--split-per-abi`
- Build iOS IPA via xcodebuild archive + export
- Upload APK to Google Drive using rclone with `dev/prod/uat` folder structure
- Upload IPA to Diawi with polling until processed
- Auto-copy Diawi link to clipboard on macOS
