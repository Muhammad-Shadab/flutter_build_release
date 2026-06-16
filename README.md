# flutter_build_release

A CLI tool that builds your Flutter app (APK + IPA) and distributes it — uploads APKs to Google Drive and IPAs to Diawi — all from one command.

---

## What it does

| Step | What happens |
|------|-------------|
| 1 | Asks you a few questions (platform, app path, upload options) |
| 2 | Runs `flutter build apk` or `flutter build ios` for you |
| 3 | For Android: uploads the APK to a Google Drive folder you choose |
| 4 | For iOS: archives and exports the IPA, then uploads to Diawi and copies the link to your clipboard |

---

## Before you start — Setup Checklist

Go through this once. After setup, the tool works every time with just `flutter_build_release`.

---

### 1. Install Dart

```bash
# Check if you already have it
dart --version

# If not, install Flutter (includes Dart)
# https://flutter.dev/docs/get-started/install
```

---

### 2. Install this tool (one command)

Download and run the install script — it activates the package **and** adds it to your PATH automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/Muhammad-Shadab/flutter_build_release/main/install.sh | bash
```

Or if you cloned the repo:

```bash
bash install.sh
```

That's all. No manual PATH editing needed.

---

### 3. Know your Flutter app directory path

This is the folder that contains your app's `pubspec.yaml` file.

```
my_project/
├── apps/
│   └── my_app/          ← this is your app-dir
│       ├── pubspec.yaml
│       ├── lib/
│       └── ios/
```

To find the full path, open a terminal inside that folder and run:

```bash
pwd
# Example output: /Users/john/projects/my_app
```

---

### 4. Choose an app name

This is just a label used in the output file name — it can be anything.

```
Ruloans → Ruloans_June_2026_03-45-PM.apk
MyApp   → MyApp_June_2026_03-45-PM.apk
```

Use your app's display name, no spaces.

---

### 5. Google Drive setup (Android upload only)

You need two things: **rclone** installed and a **Drive folder ID**.

#### Install rclone

```bash
brew install rclone
```

#### Connect rclone to your Google Drive

```bash
rclone config
```

Follow the prompts:
1. Press `n` for new remote
2. Name it `gdrive`
3. Choose `drive` (Google Drive)
4. Leave client ID and secret blank (just press Enter)
5. Choose scope `1` (full access)
6. Leave root folder blank
7. Press `n` for advanced config
8. Press `y` to use auto config — a browser window opens, log in with your Google account
9. Press `n` (not a team drive)
10. Press `y` to confirm

#### Get your Drive folder ID

Open the Google Drive folder where you want APKs uploaded, then look at the URL:

```
https://drive.google.com/drive/folders/1wP7TZvEoOOo2W_GPVghbhZWQgYcWmF8F
                                        ↑ this part is your folder ID
```

Copy the ID after `/folders/`.

---

### 6. Diawi token (iOS upload only)

Diawi lets you share IPAs with testers via a link.

1. Go to [diawi.com](https://www.diawi.com) and create a free account
2. Go to **Account → API Access Tokens**
3. Create a token and copy it

---

### 7. Apple Team ID (iOS builds only)

1. Go to [developer.apple.com](https://developer.apple.com)
2. Sign in → click your name top-right → **Membership details**
3. Copy the **Team ID** (looks like `UC2HYA24R2`)

---

### 8. Xcode command-line tools (iOS only)

```bash
xcode-select --install
```

---

## Quick start

Once setup is done, just run:

```bash
flutter_build_release
```

The tool will ask you:

```
  What do you want to build?
  1) Android only
  2) iOS only
  3) Both Android + iOS

  Enter choice [1/2/3]:

  Flutter app directory path:
  → paste the path from Step 3, e.g. /Users/john/projects/my_app

  App name (used in output file names):
  → e.g. MyApp

  Upload APK to Google Drive? [y/N]:
  → y

  Google Drive folder ID:
  → paste the ID from Step 5

  Choose flavour:
  0) dev
  1) prod
  2) uat

  Apple Developer Team ID:
  → paste the ID from Step 7

  Upload IPA to Diawi? [y/N]:
  → y

  Diawi API token:
  → paste the token from Step 6
```

That's it — the tool builds and uploads everything automatically.

---

## Non-interactive mode (for CI / scripts)

You can skip all prompts by passing flags:

```bash
flutter_build_release \
  --platform both \
  --app-dir /path/to/my_app \
  --app-name MyApp \
  --team-id UC2HYA24R2 \
  --diawi-token YOUR_DIAWI_TOKEN \
  --upload-drive \
  --drive-folder-id 1wP7TZvEoOOo2W_GPVghbhZWQgYcWmF8F \
  --flavour prod
```

You can mix flags and prompts — any flag you omit will be asked interactively.

---

## All flags

| Flag | Description | Default |
|------|-------------|---------|
| `--platform`, `-p` | `android`, `ios`, or `both` | prompted |
| `--app-dir`, `-d` | Path to Flutter app (folder with pubspec.yaml) | prompted |
| `--app-name`, `-n` | Label used in output file names | prompted |
| `--upload-drive` | Upload APK to Google Drive | prompted |
| `--drive-folder-id` | Google Drive folder ID | prompted |
| `--flavour`, `-f` | `dev`, `prod`, or `uat` | prompted |
| `--rclone-remote` | rclone remote name | `gdrive` |
| `--team-id`, `-t` | Apple Developer Team ID | prompted |
| `--scheme` | Xcode scheme | `Runner` |
| `--export-method` | `development`, `release-testing`, `app-store` | `development` |
| `--diawi-token` | Diawi API token | prompted |
| `--help`, `-h` | Print usage | |

---

## Google Drive folder structure

APKs are organized automatically inside your chosen folder:

```
<your-drive-folder>/
└── dev/
    └── 2026/
        └── June/
            └── MyApp_June_2026_03-45-PM.apk
```

---

## iOS export methods

| Value | Use case |
|-------|----------|
| `development` | Xcode auto-manages profiles; works with Diawi |
| `release-testing` | Ad Hoc / TestFlight internal testing |
| `app-store` | App Store submission |

---

## License

MIT
