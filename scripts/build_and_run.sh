#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build and run the lightweight macOS YESSS tray app (SwiftPM, no Xcode project needed).

Usage:
  scripts/build_and_run.sh [options]

Options:
  --build-only     Build only (do not run the app).
  --run-only       Run only (skip explicit build step).
  --release        Build/Run in release configuration.
  -h, --help       Show this help.
EOF
}

mode="build-and-run"
configuration="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only)
      mode="build-only"
      ;;
    --run-only)
      mode="run-only"
      ;;
    --release)
      configuration="release"
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
  echo "This script must be run on macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode command line tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_args=(--package-path "$package_root" --configuration "$configuration")

if [[ "$mode" != "run-only" ]]; then
  echo "Building YesssTrayApp ($configuration)..."
  swift build "${build_args[@]}"

  if [[ "$mode" == "build-only" ]]; then
    echo "Build finished. Run with:"
    echo "  swift run --package-path '$package_root' --configuration '$configuration' YesssTrayApp"
    exit 0
  fi
fi

echo "Launching YesssTrayApp..."
exec swift run --package-path "$package_root" --configuration "$configuration" YesssTrayApp
