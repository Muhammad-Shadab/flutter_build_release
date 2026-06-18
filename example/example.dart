// flutter_release_manager — Usage Examples
//
// This package is a CLI tool. You do not import it into your Flutter project.
// You activate it globally and run it from your terminal.
//
// ─────────────────────────────────────────────────────────────────────────────
// INSTALLATION
// ─────────────────────────────────────────────────────────────────────────────
//
//   dart pub global activate flutter_release_manager
//
// ─────────────────────────────────────────────────────────────────────────────
// ONE-TIME SETUP (run once per machine)
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager init
//
//   This command:
//     1. Installs rclone automatically (macOS via Homebrew, Linux via apt-get)
//     2. Opens your browser for Google Drive sign-in — one click, then done
//     3. Lets you choose a destination folder in your Google Drive
//     4. Optionally saves your Diawi token for iOS IPA distribution
//
// ─────────────────────────────────────────────────────────────────────────────
// BUILD AND UPLOAD (run inside your Flutter project)
// ─────────────────────────────────────────────────────────────────────────────
//
//   cd /path/to/your_flutter_app
//   flutter_release_manager
//
//   What happens:
//     - Detects your project and app name from pubspec.yaml
//     - Asks which platform to build (Android / iOS / Both)
//     - Runs flutter build apk --split-per-abi
//     - Uploads the APK to Google Drive under <folder>/YYYY/Month/AppName_date.apk
//     - Returns a shareable Google Drive link
//
// ─────────────────────────────────────────────────────────────────────────────
// HEALTH CHECK
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager doctor
//
//   Checks: flutter, rclone, Drive remote, Drive connection, folder, Diawi
//
// ─────────────────────────────────────────────────────────────────────────────
// ANDROID ONLY — skip prompts
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager --platform android --upload-drive
//
// ─────────────────────────────────────────────────────────────────────────────
// iOS ONLY
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager --platform ios --team-id ABCD1234EF --diawi-token YOUR_TOKEN
//
// ─────────────────────────────────────────────────────────────────────────────
// UPLOAD WITHOUT REBUILDING (skip-build)
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager --platform android --upload-only
//
//   Uploads the last built APK without running flutter build again.
//   Useful when the build succeeded but upload failed, or to re-share an artifact.
//
// ─────────────────────────────────────────────────────────────────────────────
// CI / NON-INTERACTIVE (all flags, no prompts)
// ─────────────────────────────────────────────────────────────────────────────
//
//   flutter_release_manager \
//     --platform both \
//     --app-dir /path/to/my_app \
//     --app-name MyApp \
//     --team-id ABCD1234EF \
//     --diawi-token YOUR_DIAWI_TOKEN \
//     --upload-drive
//
// ─────────────────────────────────────────────────────────────────────────────
// See the full documentation at:
// https://pub.dev/packages/flutter_release_manager
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // This package is a CLI tool — there is no Dart API to call.
  // Run it from your terminal as shown in the comments above.
  //
  // To get started:
  //   dart pub global activate flutter_release_manager
  //   flutter_release_manager init
  print('Run flutter_release_manager from your terminal.');
  print('See: https://pub.dev/packages/flutter_release_manager');
}
