# flutter_release_manager

**Build, package, and distribute Flutter releases with a single command.**

[![pub.dev](https://img.shields.io/pub/v/flutter_release_manager.svg)](https://pub.dev/packages/flutter_release_manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](https://pub.dev/packages/flutter_release_manager)

---

## The Problem

Every time you finish a feature or fix a bug, your QA team needs the latest build. Without a tool, you do this manually:

1. Run `flutter build apk` in the terminal — wait 3 minutes
2. Navigate to `build/app/outputs/flutter-apk/` in Finder/Explorer
3. Upload the APK file to Google Drive by dragging and dropping
4. Wait for the upload to finish
5. Right-click → Get shareable link
6. Copy the link and paste it in Slack/WhatsApp
7. Tell the QA team which version it is

**With flutter_release_manager:**

```bash
cd your_flutter_app
flutter_release_manager
```

Done. The APK is built, uploaded, and a shareable link is printed in your terminal — in one command.

---

## What It Does

| Without this tool                      | With this tool                          |
|----------------------------------------|-----------------------------------------|
| Build manually, upload manually        | One command does everything             |
| Remember folder structure yourself     | Automatically organized by year/month   |
| Create links manually                  | Link generated and printed automatically|
| Android and iOS are separate workflows | Both platforms in one command           |
| Re-enter Drive folder every time       | Remembers your settings between runs    |

---

## Features

- **Android APK** — builds with `--split-per-abi` (one APK per device type), uploads to Google Drive
- **iOS IPA** — archives with Xcode, exports, uploads to Diawi for testers to install with one tap
- **Google Drive upload** — automatic browser sign-in, no Google Cloud Console required
- **Diawi upload** — iOS testers get a simple install link, no App Store needed
- **Auto-installs rclone** — the upload tool is set up for you, you don't configure it
- **Upload retry** — 3 automatic retries if the internet drops during upload
- **Progress display** — watch the build and upload happen in real time
- **Settings memory** — answers are saved, so the second run asks almost nothing
- **CI/CD ready** — pass all settings as flags to skip every prompt
- **Cross-platform** — works on macOS, Linux, and Windows

---

## Before You Start

You need these installed before using this package:

| Requirement | What it is | How to install |
|-------------|------------|----------------|
| **Flutter & Dart** | The Flutter framework and Dart SDK | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| **rclone** (Android upload) | A tool that uploads files to Google Drive | **Automatic** — `init` installs it for you |
| **Xcode** (iOS only, macOS only) | Apple's IDE, needed to build iOS apps | [Mac App Store → Xcode](https://apps.apple.com/app/xcode/id497799835) |

> **Note for iOS builds:** After installing Xcode, run this once:
> ```bash
> xcode-select --install
> ```

You do **not** need:
- A Google Cloud account
- An OAuth client ID or secret
- A service account key file
- Any prior rclone experience

---

## Step 1 — Install the Package

Open your terminal and run:

```bash
dart pub global activate flutter_release_manager
```

**What this does:** Downloads and installs the `flutter_release_manager` command on your machine globally. You can now use it from any directory.

**Expected output:**

```
Resolving dependencies...
Downloading flutter_release_manager 3.0.0...
Building package executables...
Built flutter_release_manager:flutter_release_manager.
Installed executable flutter_release_manager.
Activated flutter_release_manager 3.0.0.
```

**Make sure the command is available.** If you get "command not found" after installing, add the Dart pub global bin directory to your PATH:

- **macOS / Linux** — add to `~/.zshrc` or `~/.bashrc`:
  ```bash
  export PATH="$PATH:$HOME/.pub-cache/bin"
  ```
  Then restart your terminal or run `source ~/.zshrc`.

- **Windows** — add `%LOCALAPPDATA%\Pub\Cache\bin` to your System PATH.

**Verify it works:**

```bash
flutter_release_manager --help
```

---

## Step 2 — One-Time Setup


> Run this **once per machine**. After setup, you never need to run it again unless you want to change your Drive folder or Diawi token.

```bash
flutter_release_manager init
```

The setup wizard walks you through 5 steps. Here is exactly what happens at each step:

---

### Step 2.1 — rclone Installation

**What is rclone?**
rclone is a free, open-source program that uploads files to cloud storage services like Google Drive. It handles the connection between your machine and your Google Drive account. `flutter_release_manager` uses rclone internally to upload APKs — you never interact with rclone directly.

**What happens:**
The wizard checks if rclone is installed. If not, it installs it automatically:
- macOS: installs via Homebrew
- Linux: installs via apt-get
- Windows: shows instructions with download links

**Expected output (rclone already installed):**
```
╔══════════════════════════════════════════════╗
  Step 1 — rclone
╚══════════════════════════════════════════════╝

  ✓  rclone — rclone v1.67.0
```

**Expected output (rclone not installed, macOS):**
```
╔══════════════════════════════════════════════╗
  Step 1 — rclone
╚══════════════════════════════════════════════╝

  ⚠  rclone not found — attempting automatic installation...

  →  Installing rclone via Homebrew...
  [homebrew output...]
  ✓  rclone installed — rclone v1.67.0
```

**Troubleshooting:**
- *macOS — Homebrew not found:* Install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- *Linux — apt-get fails:* Install manually from [rclone.org/install](https://rclone.org/install/)

---

### Step 2.2 — Google Drive Sign-in

**What happens:**
The wizard opens your web browser automatically. You sign in to your Google account and click **Allow** to give rclone permission to access your Google Drive. The permission is saved securely on your machine — you never need to sign in again.

**Why is sign-in required?**
APKs are uploaded to your Google Drive. Google requires authentication to access your files. Unlike manual setup, you don't need to create a Google Cloud project or generate API keys — rclone uses its own built-in credentials and handles everything through the standard Google sign-in screen you already know.

**Expected output:**
```
╔══════════════════════════════════════════════╗
  Step 2 — Google Drive Remote
╚══════════════════════════════════════════════╝

  ─── Google Drive Sign-in ──────────────────────────────

  Your browser will open for Google sign-in.
  Sign in with the account that owns your Drive folder,
  then click Allow — this tool will resume automatically.

  →  Opening browser for Google OAuth (waiting up to 5 min)...

  If your browser doesn't open automatically go to the following link:
  http://127.0.0.1:53682/auth?...
  Log in and authorize rclone for access
  Waiting for code...
  Got code

  ✓  Authorization complete.
  →  Saving credentials to rclone remote "flutter_release_manager"...
  ✓  Remote "flutter_release_manager" configured.
```

**What the browser shows:**
A standard Google sign-in page, then a screen asking you to allow access to Google Drive. Click **Allow**.

**Troubleshooting:**
- *Browser doesn't open:* Copy the `http://127.0.0.1:...` link from the terminal and paste it into your browser manually.
- *Authorization failed:* Make sure you clicked **Allow** (not Deny). Re-run `flutter_release_manager init`.
- *Times out after 5 minutes:* The browser window was left open too long. Re-run `flutter_release_manager init` and complete sign-in promptly.

---

### Step 2.3 — Drive Connection Verification

**What happens:**
The wizard confirms that the sign-in worked by connecting to your Google Drive and displaying your storage quota.

**Expected output:**
```
╔══════════════════════════════════════════════╗
  Step 3 — Verify Connection
╚══════════════════════════════════════════════╝

  →  Verifying Google Drive connection...
  ✓  Google Drive — connected
   ℹ  Total:   15 GB
   ℹ  Used:    4.2 GB
   ℹ  Free:    10.8 GB
```

---

### Step 2.4 — Choose Your Drive Folder

**What happens:**
The wizard lists the folders at the top level of your Google Drive and asks you to choose one. APKs will be uploaded inside that folder, organized by year and month automatically.

**Example input:**
```
╔══════════════════════════════════════════════╗
  Step 4 — Drive Folder
╚══════════════════════════════════════════════╝

  Fetching top-level folders from your Google Drive...

  1. Personal
  2. QA Builds
  3. Projects
  4. Enter folder name manually

  Select destination folder [1-4]: 2
  ✓  Drive folder: QA Builds
```

**If your folder doesn't appear in the list:**
Choose "Enter folder name manually" and type the folder name. The folder will be created automatically on the first upload if it doesn't exist yet.

**Where files will appear:**
```
QA Builds/
└── 2026/
    └── June/
        ├── MyApp_2026_06_18_1430.apk   ← uploaded on Jun 18 at 14:30
        └── MyApp_2026_06_19_0920.apk   ← uploaded on Jun 19 at 09:20
```

---

### Step 2.5 — Diawi Token (iOS only — optional)

**What is Diawi?**
[Diawi](https://www.diawi.com) is a web service for distributing iOS and Android builds to testers. After uploading your IPA file, Diawi gives you a short link like `https://i.diawi.com/AbCdEf`. Testers tap that link on their iPhone and the app installs directly — no App Store, no TestFlight, no developer account needed for testers.

**Do I need Diawi?**
- **Android only?** → No. APKs go to Google Drive. Press Enter to skip.
- **iOS builds?** → Yes, this is the recommended way to share iOS builds with testers.

**How to get a Diawi token:**
1. Go to [diawi.com](https://www.diawi.com) and create a free account
2. Log in → click your name → **Account → API Access Tokens**
3. Click **Create new token** and copy it

**Example input:**
```
╔══════════════════════════════════════════════╗
  Step 5 — Diawi Token (optional)
╚══════════════════════════════════════════════╝

  ℹ  Diawi gives testers an install link for iOS builds.
  ℹ  Sign up at diawi.com → Account → API Access Tokens.
  ℹ  Press Enter to skip if you don't need iOS uploads.

  Diawi API token (or Enter to skip): a1b2c3d4e5f6...
  ✓  Diawi token saved.
```

---

### Setup Complete

After all 5 steps, you'll see:

```
  ✓  Configuration saved to ~/.config/flutter_release_manager/config.json

  Setup complete.
  Run flutter_release_manager to build and upload.
```

Your settings are stored at `~/.config/flutter_release_manager/config.json`. You never need to run `init` again unless you want to change your Drive folder or Diawi token.

---

## Step 3 — Build and Upload

Navigate into your Flutter project and run:

```bash
cd /path/to/your_flutter_project
flutter_release_manager
```

**What happens — complete example session:**

```
╔══════════════════════════════════════════════╗
  flutter_release_manager  v3
  Build · Archive · Distribute
╚══════════════════════════════════════════════╝

  ✓  Flutter project detected: /Users/shadab/projects/my_app

  ─── Platform ────────────────────────────────────────────

  What do you want to build?
  1) Android only  — generates APK
  2) iOS only      — generates IPA
  3) Both          — APK + IPA

  Enter choice [1/2/3]: 1

  ─── Google Drive Upload ──────────────────────────────────

  ℹ  APKs are uploaded via rclone — no OAuth setup needed.
  ℹ  Run flutter_release_manager init once to configure Drive.
  ℹ  Skip to keep the APK on your machine.

  Upload APK to Google Drive after building? [y/N]: y
  ✓  Drive folder: QA Builds

╔══════════════════════════════════════════════╗
  Pre-flight checks
╚══════════════════════════════════════════════╝

  ✓  flutter found
  ✓  rclone found — rclone v1.67.0
  ✓  rclone remote "flutter_release_manager" configured
  ✓  Google Drive — connected

╔══════════════════════════════════════════════╗
  Build Summary
╚══════════════════════════════════════════════╝

  Platform      Android
  App dir       /Users/shadab/projects/my_app
  App name      MyApp

  Android
    Drive upload  Yes (via rclone)
    Folder        QA Builds

  Press Enter to start the build, or Ctrl+C to cancel... ↵

╔══════════════════════════════════════════════╗
  Android APK  (2026-06-18_14-30)
╚══════════════════════════════════════════════╝

  →  Running: flutter build apk --split-per-abi

  [... flutter build output ...]

  Output APKs:
  ✓  app-arm64-v8a-release.apk    (28.3 MB)   ← modern phones
  ✓  app-armeabi-v7a-release.apk  (26.1 MB)   ← older phones
  ✓  app-x86_64-release.apk       (29.0 MB)   ← emulators

╔══════════════════════════════════════════════╗
  Uploading APK to Google Drive
╚══════════════════════════════════════════════╝

  →  Destination : QA Builds/2026/June/MyApp_2026_06_18_1430.apk
  →  Local file  : app-arm64-v8a-release.apk (28.3 MB)
  →  Uploading (attempt 1/3)...

  [rclone transfer progress...]

  ✓  Upload complete.

╔══════════════════════════════════════════════╗
  Upload completed successfully
╚══════════════════════════════════════════════╝

  APK Name:
  MyApp_2026_06_18_1430.apk

  Google Drive URL:
  https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStU.../view

╔══════════════════════════════════════════════╗
  Build complete
╚══════════════════════════════════════════════╝

  Android APK:
  https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStU.../view
```

Copy the Google Drive URL and send it to your QA team.

> **Second run and beyond:** The tool remembers your platform choice and folder. Just press Enter to accept the defaults — the build starts in seconds.

---

## Command Reference

### `flutter_release_manager init`

| | |
|--|--|
| **Purpose** | One-time machine setup: install rclone, sign into Google Drive, choose folder, save Diawi token |
| **When to run** | Once per machine. Re-run to change your Drive folder or Diawi token. |
| **Requires** | Internet connection, Google account |

```bash
flutter_release_manager init
```

---

### `flutter_release_manager doctor`

| | |
|--|--|
| **Purpose** | Check that all prerequisites are installed and configured correctly |
| **When to run** | After installation to verify setup, or when something stops working |
| **Requires** | Nothing — just reads system state |

```bash
flutter_release_manager doctor
```

**Example output (all good):**
```
  ✓  flutter          flutter found
  ✓  rclone           rclone v1.67.0
  ✓  Drive remote     remote "flutter_release_manager" configured
  ✓  Drive connection Google Drive reachable
  ✓  Drive folder     "QA Builds" accessible
  ⚠  Diawi token      not set — iOS Diawi upload will be skipped

  ✓  All checks passed. Ready to build and upload.
```

**Example output (problem found):**
```
  ✓  flutter          flutter found
  ✓  rclone           rclone v1.67.0
  ✗  Drive remote     remote "flutter_release_manager" not found
                 Fix: Run: flutter_release_manager init

  ⚠  Some checks failed. Run: flutter_release_manager init
```

---

### `flutter_release_manager`

| | |
|--|--|
| **Purpose** | Build your Flutter app and upload the artifacts |
| **When to run** | From inside your Flutter project directory, whenever you want to share a build |
| **Requires** | `init` must have been run at least once |

```bash
cd /path/to/your_flutter_project
flutter_release_manager
```

---

### `flutter_release_manager --platform android`

| | |
|--|--|
| **Purpose** | Build and upload Android APK only, skip iOS entirely |
| **When to run** | When you only need to share with Android testers |

```bash
flutter_release_manager --platform android --upload-drive
```

---

### `flutter_release_manager --platform ios`

| | |
|--|--|
| **Purpose** | Build and upload iOS IPA only, skip Android entirely |
| **When to run** | When you only need to share with iOS testers (macOS only) |

```bash
flutter_release_manager --platform ios --team-id ABCD1234EF
```

---

### `flutter_release_manager --skip-build`

| | |
|--|--|
| **Purpose** | Upload the artifact from your last build without rebuilding |
| **When to run** | Build succeeded but upload failed. Or you want to re-share the same build. |

```bash
flutter_release_manager --platform android --skip-build
```

---

### `flutter_release_manager --upload-only`

Same as `--skip-build`. Both flags do the same thing.

```bash
flutter_release_manager --platform android --upload-only
```

---

## All Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--platform` | `-p` | `android`, `ios`, or `both` | prompted |
| `--app-dir` | `-d` | Path to Flutter project (where `pubspec.yaml` lives) | auto-detected |
| `--app-name` | `-n` | Label used in APK/IPA file names | from `pubspec.yaml` |
| `--upload-drive` | | Upload APK to Google Drive | prompted |
| `--team-id` | `-t` | Apple Developer Team ID (iOS only) | prompted |
| `--scheme` | | Xcode scheme name | `Runner` |
| `--export-method` | | `development` \| `release-testing` \| `app-store` | `development` |
| `--diawi-token` | | Diawi API token for IPA upload | from config |
| `--skip-build` | | Upload last artifact, skip the build step | `false` |
| `--upload-only` | | Alias for `--skip-build` | `false` |
| `--help` | `-h` | Print help text | |

---

## Non-Interactive Mode (CI/CD)

Pass all values as flags to skip every prompt. Useful in GitHub Actions, Bitrise, Codemagic, or any CI pipeline.

```bash
flutter_release_manager \
  --platform android \
  --app-dir /path/to/my_app \
  --app-name MyApp \
  --upload-drive
```

For iOS:

```bash
flutter_release_manager \
  --platform ios \
  --app-dir /path/to/my_app \
  --app-name MyApp \
  --team-id ABCD1234EF \
  --diawi-token YOUR_TOKEN \
  --export-method development
```

Both platforms:

```bash
flutter_release_manager \
  --platform both \
  --app-dir /path/to/my_app \
  --app-name MyApp \
  --team-id ABCD1234EF \
  --diawi-token YOUR_TOKEN \
  --upload-drive
```

---

## Configuration Files

### Machine Configuration

**Location:** `~/.config/flutter_release_manager/config.json` (macOS / Linux)
**Location:** `%APPDATA%\flutter_release_manager\config.json` (Windows)

**What it stores:**
- Your chosen Google Drive folder name
- Your Diawi API token (if saved)
- The rclone remote name

**Set by:** `flutter_release_manager init`

**Security:** The directory has permission `700` (owner-only access) and the file has permission `600` (owner-read-only). This is set automatically.

**Example contents:**
```json
{
  "folderName": "QA Builds",
  "remote": "flutter_release_manager",
  "diawiToken": "a1b2c3d4..."
}
```

---

### Project Configuration

**Location:** `<your_flutter_app>/.flutter_release_manager_config.json`

**What it stores:**
- Last used platform (android / ios / both)
- App name
- Apple Team ID
- Xcode scheme
- Export method

**Set by:** Automatically saved after each successful run.

**Security:** Contains no secrets. The file is added to `.gitignore` automatically.

**Example contents:**
```json
{
  "platform": "android",
  "appName": "MyApp",
  "scheme": "Runner",
  "exportMethod": "development"
}
```

---

## Google Drive Folder Structure

APKs are organized automatically inside your chosen folder:

```
QA Builds/                        ← your chosen folder
└── 2026/                         ← year (created automatically)
    └── June/                     ← month (created automatically)
        ├── MyApp_2026_06_18_1430.apk   ← build from Jun 18 at 14:30
        ├── MyApp_2026_06_19_0920.apk   ← build from Jun 19 at 09:20
        └── MyApp_2026_06_25_1715.apk   ← build from Jun 25 at 17:15
```

The arm64-v8a APK is uploaded (covers all modern Android phones). A fallback to armeabi-v7a is used if arm64 is not available.

---

## iOS Distribution

### Prerequisites for iOS Builds

1. **macOS only** — iOS builds require Xcode, which only runs on macOS.
2. **Install Xcode** from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835).
3. **Install command-line tools:**
   ```bash
   xcode-select --install
   ```
4. **Apple Developer Account** — needed to sign the app. Free accounts work for development builds. Paid accounts ($99/year) are needed for distribution.
5. **Apple Team ID** — a 10-character code like `UC2HYA24R2`. Find it at:
   [developer.apple.com](https://developer.apple.com) → Sign in → click your name (top right) → **Membership details** → **Team ID**

### Export Methods

| Value | Use case |
|-------|----------|
| `development` | Testing on registered devices. Xcode manages provisioning profiles automatically. Works with Diawi. |
| `release-testing` | Ad Hoc distribution. For sharing with up to 100 specific devices. |
| `app-store` | Final build for App Store submission. |

Use `development` unless you know you need something else.

---

## Troubleshooting

### `flutter: command not found`

**Problem:** The `flutter` command is not recognized.
**Cause:** Flutter is not installed, or its `bin` directory is not in your PATH.
**Solution:**
1. Install Flutter from [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
2. Follow the "Update your path" step in the Flutter installation guide
3. Restart your terminal and run `flutter --version` to verify

---

### `rclone not found` after running `init`

**Problem:** rclone installation failed.
**Cause:** Homebrew (macOS) or apt-get (Linux) failed, or you're on Windows.
**Solution:**
- **macOS:** Install Homebrew first: `https://brew.sh`, then run `flutter_release_manager init` again.
- **Linux:** Run `sudo apt-get install rclone` manually, then `flutter_release_manager init`.
- **Windows:** Download from [rclone.org/install/#windows](https://rclone.org/install/#windows), install, then run `flutter_release_manager init`.

---

### `Google Drive authentication failed`

**Problem:** The sign-in step failed or timed out.
**Cause:** You may have clicked Deny, the browser window was left open too long, or network issues occurred.
**Solution:**
```bash
flutter_release_manager init
```
Run init again. Complete the sign-in promptly after the browser opens (within 5 minutes).

---

### `Remote "flutter_release_manager" not found`

**Problem:** The Google Drive connection is not configured.
**Cause:** `init` was not completed, or the rclone config was deleted.
**Solution:**
```bash
flutter_release_manager init
```

---

### Drive folder is not visible in the list during `init`

**Problem:** Your target folder doesn't appear in the list.
**Cause:** The folder may be inside another folder (not at the root of Drive), or Drive hasn't synced.
**Solution:**
- Choose **"Enter folder name manually"** and type the name exactly
- The folder will be created automatically on the first upload if it doesn't exist

---

### `Diawi upload failed`

**Problem:** The iOS IPA was not uploaded to Diawi.
**Cause:** The Diawi token is expired, incorrect, or Diawi's servers are temporarily unavailable.
**Solution:**
1. Go to [diawi.com](https://www.diawi.com) → **Account → API Access Tokens**
2. Create a new token
3. Run `flutter_release_manager init` to update the saved token

---

### `Archive failed` or `Export failed` (iOS)

**Problem:** The iOS build failed at the Xcode archive step.
**Cause:** Misconfigured Team ID, missing provisioning profiles, or Xcode command-line tools not installed.
**Solution:**
1. Verify your Team ID is exactly 10 uppercase characters (e.g. `UC2HYA24R2`)
2. Run `xcode-select --install` to update command-line tools
3. Open Xcode and make sure your project builds manually: **Product → Archive**
4. Check that you have a valid signing certificate in **Xcode → Settings → Accounts**

---

### `Flutter build apk` fails

**Problem:** The Android build fails.
**Cause:** Code errors, missing SDK, or Gradle issues.
**Solution:** Run the build command directly to see the raw error:
```bash
flutter build apk --split-per-abi
```
Fix any errors shown, then run `flutter_release_manager` again.

---

### `Doctor shows green but upload fails`

**Problem:** All checks pass but uploading fails.
**Cause:** The Google Drive token may have expired, or network issues during upload.
**Solution:**
```bash
# Re-authenticate Google Drive
flutter_release_manager init

# Or retry the upload without rebuilding
flutter_release_manager --platform android --upload-only
```

---

### `command not found: flutter_release_manager` (after installing)

**Problem:** The command is not found even after running `dart pub global activate`.
**Cause:** The Dart global bin directory is not in your PATH.
**Solution:** Add the pub cache bin to your PATH:
```bash
# macOS / Linux — add to ~/.zshrc or ~/.bashrc:
export PATH="$PATH:$HOME/.pub-cache/bin"

# Then reload:
source ~/.zshrc
```
On Windows, add `%LOCALAPPDATA%\Pub\Cache\bin` to your System PATH via **Control Panel → Environment Variables**.

---

## FAQ

**Do I need a Google Cloud Console account?**
No. This tool uses rclone's built-in credentials. You sign in with the regular Google sign-in page — no Cloud Console, no project, no API key.

**Do I need to know rclone?**
No. rclone is installed and configured automatically. You never interact with it directly.

**Do I need OAuth credentials?**
No. This is the whole point of the tool. The standard Google sign-in in your browser is all that's required.

**Can I use this with a Google Workspace (G Suite) account?**
Yes. Sign in with your Workspace account during `init`. If your organization restricts external app access, ask your admin to allow rclone.

**Can I upload to Shared Drives?**
Yes. Shared Drives appear in your Google Drive folder list during `init`. Select the shared folder.

**Can I upload Android only and skip iOS?**
Yes. Choose `1) Android only` when prompted, or pass `--platform android`.

**Can I skip Diawi?**
Yes. Press Enter when asked for a Diawi token. iOS builds will still work — the IPA will be saved locally but not uploaded.

**Can I use multiple Google accounts?**
One account per machine. To switch accounts, run `flutter_release_manager init` — it will prompt for a new sign-in.

**Is my Google token stored securely?**
The token is stored by rclone in its configuration file with restricted file permissions (`600`). It never touches your code or your project directory.

**Can I use this in CI/CD?**
Yes, but CI requires a pre-configured rclone remote. Set up on a developer machine first, then export the rclone config to your CI environment. See the [All Flags](#all-flags) section for non-interactive usage.

**What APK gets uploaded?**
The `arm64-v8a` APK (covers all phones made after 2014). If it's not available, `armeabi-v7a` is used as a fallback.

**Does this work on Windows?**
Yes, for Android builds. iOS builds require macOS (Xcode requirement from Apple).

---

## Screenshots

> **Recommended screenshots to add to your documentation:**

| Screenshot | Suggested filename | Caption |
|------------|-------------------|---------|
| Full `init` terminal session | `doc/screenshots/init.png` | "One-time setup: installs rclone, signs into Google Drive, picks folder" |
| `doctor` output (all green) | `doc/screenshots/doctor.png` | "Health check: all systems ready" |
| Build progress + upload progress | `doc/screenshots/build.png` | "Building APK and uploading to Google Drive" |
| Final output with Drive link | `doc/screenshots/result.png` | "Done: shareable Google Drive link ready to paste" |

To take screenshots that render well on pub.dev: use a terminal with a dark theme and a font size of at least 14pt.

---

## Migration from flutter_build_release

If you used the previous `flutter_build_release` package, migration is fully automatic.

**What migrates automatically on first run:**

| Old | New | Action |
|-----|-----|--------|
| `~/.config/flutter_build_release/config.json` | `~/.config/flutter_release_manager/config.json` | Copied automatically |
| `.flutter_build_release_config.json` | `.flutter_release_manager_config.json` | Copied automatically |
| rclone remote `flutter_build_release` | rclone remote `flutter_release_manager` | Migrated, **no re-authentication** |

You keep your Google Drive access. You don't sign in again.

**After migration, remove the old package:**

```bash
dart pub global deactivate flutter_build_release
```

---

## License

MIT — see [LICENSE](LICENSE)

---

*Made for Flutter teams who would rather ship than wait.*
