# Repository Instructions

## Project

ClipLy is a macOS clipboard history app built with SwiftUI and AppKit.
The Xcode project is `ClipboardHistory.xcodeproj`; the product name and app name are `ClipLy`.

## Build

Use this command from the repository root:

```bash
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug build
```

The built app is emitted under Xcode DerivedData as `ClipLy.app`.

## App Behavior

- The app runs primarily from the menu bar.
- It stores clipboard history for text, images, and files.
- Retention is configurable from 1 day to 1 month.
- The launcher is Spotlight-style and supports keyboard navigation:
  - `Escape` closes the launcher.
  - Up/down arrows move through results.
  - Left/right arrows switch categories.
  - `Enter` restores and pastes the selected item.
- Pasting into the active app uses macOS Accessibility permission.
- Launch at login and Dock icon visibility are configurable in Settings.

## Storage

App data is stored in:

```text
~/Library/Application Support/ClipLy
```

Older `ClipboardHistory` app support data may be migrated by the app.

## Assets

- App icon assets live in `ClipboardHistory/Resources/Assets.xcassets/AppIcon.appiconset`.
- The 1024px source app icon is `ClipboardHistory/Resources/Assets.xcassets/cliply-appicon-source.png`.
- Menu bar icon assets live in `ClipboardHistory/Resources/Assets.xcassets/MenuBarIcon.imageset`.
## Code Style

- Prefer existing SwiftUI/AppKit patterns already present in the project.
- Keep the app lightweight: avoid background work beyond pasteboard polling, retention cleanup, and user-triggered search/UI.
- Do not add App Store, iCloud, analytics, or password-exclusion features unless explicitly requested.
- Keep generated build outputs and local macOS/Xcode metadata out of git.
