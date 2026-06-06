#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build and install YESSS Quota Tray as a macOS .app bundle.

Usage:
  scripts/install_app.sh [options]

Options:
  --target DIR     Install into DIR (default: /Applications, falling back to ~/Applications if not writable).
  --name NAME      App bundle name without .app (default: YESSS Quota Tray).
  --no-open        Do not launch the app after installing.
  -h, --help       Show this help.
EOF
}

app_name="YESSS Quota Tray"
target_dir=""
open_after_install=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a directory" >&2; exit 1; }
      target_dir="$2"
      shift
      ;;
    --name)
      [[ $# -ge 2 ]] || { echo "--name requires an app name" >&2; exit 1; }
      app_name="$2"
      shift
      ;;
    --no-open)
      open_after_install=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer must be run on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode command line tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$target_dir" ]]; then
  if [[ -d /Applications && -w /Applications ]]; then
    target_dir="/Applications"
  else
    target_dir="$HOME/Applications"
  fi
fi

mkdir -p "$target_dir"

echo "Building YesssTrayApp (release)..."
swift build --package-path "$package_root" --configuration release

binary_path="$(swift build --package-path "$package_root" --configuration release --show-bin-path)/YesssTrayApp"
if [[ ! -x "$binary_path" ]]; then
  echo "Built executable not found: $binary_path" >&2
  exit 1
fi

bundle_path="$target_dir/$app_name.app"
contents_path="$bundle_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

rm -rf "$bundle_path"
mkdir -p "$macos_path" "$resources_path"
install -m 755 "$binary_path" "$macos_path/YesssTrayApp"

cat > "$contents_path/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>YesssTrayApp</string>
  <key>CFBundleIdentifier</key>
  <string>at.yesss.quota-tray</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>YESSS Quota Tray</string>
  <key>CFBundleDisplayName</key>
  <string>YESSS Quota Tray</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$bundle_path" >/dev/null 2>&1 || true
fi

echo "Installed: $bundle_path"

if [[ "$open_after_install" -eq 1 ]]; then
  echo "Launching app..."
  open "$bundle_path"
fi
