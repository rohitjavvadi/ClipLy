# Contributing to ClipLy

Thanks for helping improve ClipLy. Small, focused pull requests are the easiest to review and merge.

## How to Contribute

1. Find an issue labeled `good first issue` or `help wanted`.
2. Comment on the issue if you want to work on it.
3. Fork the repository.
4. Create a branch from `main`.
5. Make a focused change.
6. Build the app locally:

```bash
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -configuration Debug build
```

7. Open a pull request back to `main`.

## Pull Request Rules

- Contributors should submit changes through pull requests.
- Do not push directly to `main`.
- Keep generated build products, `.app` bundles, `.dmg` files, `.xcarchive` files, and Xcode user state out of git.
- Do not commit personal signing metadata, provisioning profiles, certificates, or machine-specific paths.
- Keep changes scoped to the issue or feature being addressed.
- Include screenshots or screen recordings for visible UI changes when helpful.

## Good First Issues

Issues labeled `good first issue` are intended to be approachable for new contributors. They should have a clear scope, expected outcome, and validation steps.

## Local App Data

ClipLy stores local app data in:

```text
~/Library/Application Support/ClipLy
```

Avoid deleting user data during development unless the task explicitly involves reset or uninstall behavior.
