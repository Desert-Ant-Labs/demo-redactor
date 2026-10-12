# AGENTS.md, Redactor

Read [`../lab/AGENTS.md`](../lab/AGENTS.md) first for the org-wide rules.

> **Write for the next reader, human or agent.**

## What this repo is

A macOS menu bar app that scans the clipboard with `Redact` from
`desert-ant-core` and holds Command V into chat, agent, and email apps when the
clipboard holds personal data.

## Rules

- **`App/Sources/Guarding` has no SwiftUI.** The watcher, the event tap, the
  finding, and the watchlist compile into the tests as well as the app.
- **The tap answers at once.** `PasteTap` runs on the main run loop, and macOS
  disables a tap that stalls. The handler compares the pasteboard's change
  count with the last scan and nothing else. Never read the pasteboard or wait
  on the model from inside it.
- **Reading `changeCount` is free; reading contents is not.** Since macOS 15.4,
  reading another app's clipboard contents can raise a system alert. Read
  contents once per change, in `ClipboardWatcher`.
- **The warning never activates the app.** `PasteWarning` uses non-activating panels,
  so the app being pasted into stays frontmost and the replayed keystroke lands
  there. Anything that calls `NSApp.activate` breaks the paste.
- **Replays carry `PasteTap.replayMarker`.** That is how the tap lets its own
  paste through. A posted event without it gets held again.
- **Sign builds you test the tap with.** The Accessibility grant is tied to the
  signature, and an ad hoc build gets a new one on every build. Set
  `REDACTOR_TEAM_ID`, or regrant in System Settings after each build.
- **Scan through `Chunking`, never `Redact` directly.** Redact finds fewer
  names in long text, so text goes in as sentence chunks of 150 characters.
- **A copied file stays a file.** Only text copies are redacted on their own;
  a file is swapped for its text only when the user asks.
- **`Redactor.xcodeproj` is generated.** Edit `project.yml` and rerun
  `xcodegen generate`.
