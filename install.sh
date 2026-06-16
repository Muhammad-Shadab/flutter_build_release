#!/bin/bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="flutter_build_release"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "  Installing flutter_build_release"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Check Dart ─────────────────────────────────────────────────────────────
if ! command -v dart &>/dev/null; then
  echo -e "  ${RED}✗${RESET}  Dart not found."
  echo -e "  ${CYAN}→${RESET}  Install Flutter (includes Dart): https://flutter.dev/docs/get-started/install"
  exit 1
fi
echo -e "  ${GREEN}✓${RESET}  Dart found: $(dart --version 2>&1 | head -1)"

# ── 2. Resolve the package directory ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/pubspec.yaml" ]; then
  # Running from the cloned/local repo
  PACKAGE_DIR="$SCRIPT_DIR"
else
  # Running via curl | bash — activate from pub.dev then locate package
  echo ""
  echo -e "  ${CYAN}→${RESET}  Fetching package from pub.dev..."
  dart pub global activate flutter_build_release
  PACKAGE_DIR="$HOME/.pub-cache/global_packages/flutter_build_release"
fi

echo -e "  ${GREEN}✓${RESET}  Package ready"

# ── 3. Compile native binary ──────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}→${RESET}  Compiling binary (this takes ~10 seconds)..."

TEMP_BIN="$(mktemp)"
cd "$PACKAGE_DIR"
dart compile exe bin/flutter_build_release.dart -o "$TEMP_BIN"

echo -e "  ${GREEN}✓${RESET}  Compiled successfully"

# ── 4. Install to /usr/local/bin ─────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}→${RESET}  Installing to $INSTALL_DIR (may ask for your password)..."

sudo mv "$TEMP_BIN" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo -e "  ${GREEN}✓${RESET}  Installed to $INSTALL_DIR/$BINARY_NAME"

# ── 5. Verify ─────────────────────────────────────────────────────────────────
echo ""
if command -v flutter_build_release &>/dev/null; then
  echo -e "  ${GREEN}${BOLD}✓ Done! flutter_build_release is ready.${RESET}"
  echo ""
  echo -e "  ${BOLD}Run:${RESET} flutter_build_release"
else
  echo -e "  ${RED}✗${RESET}  Installation failed. Try manually:"
  echo -e "  sudo mv $TEMP_BIN $INSTALL_DIR/$BINARY_NAME"
fi
echo ""
