# YESSS Quota Tray

A lightweight macOS menu bar app that shows remaining quota for a YESSS mobile subscription.

## Features

- Shows remaining main data quota directly in the menu bar.
- Opens a compact popover with all detected quota buckets.
- Refreshes quota data directly from the YESSS Kontomanager web session.
- Stores credentials in the macOS Keychain.
- Supports optional linked-number subscriber selection.
- Requires no Xcode project; builds with Swift Package Manager.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools

Install the command line tools if needed:

```bash
xcode-select --install
```

## Build and run

```bash
./scripts/build_and_run.sh
```

Useful options:

```bash
./scripts/build_and_run.sh --build-only
./scripts/build_and_run.sh --run-only
./scripts/build_and_run.sh --release
```

You can also use SwiftPM directly:

```bash
swift run YesssTrayApp
```

## Tests

```bash
swift test
```

The tests cover the local HTML extraction and quota/subscriber parsing logic. They do not contact YESSS.

## First run

1. Launch the app.
2. Right-click or Control-click the menu bar item.
3. Choose **Open Settings…**.
4. Enter your YESSS login and password.
5. Optionally enter a linked-number subscriber ID.
6. Click **Save & Refresh**.

Credentials are saved in the macOS Keychain. The app does not store credentials in files and does not write quota snapshots to disk.

## Notes

This app uses the YESSS web login flow and parses the quota page HTML. The parser is intentionally heuristic-based so it can tolerate minor layout changes.
