# Launch at login

VoiceKey is a hold-to-talk shortcut. A shortcut that is only there after you
remember to start the app is not a shortcut, so both builds get a way to open
themselves when the user signs in — off by default, one click from the sidebar
footer, and honest about the case where the OS has vetoed it.

## What the user sees

The sidebar footer already carries the utility links (Shortcut, Diagnostics log,
Help & shortcuts). One more joins them, at the top of that group, in the
bottom-left corner of the window:

```
Open at login — Off        (macOS)
Start with Windows — Off   (Windows)
```

Clicking it toggles. The word after the dash is what the OS reports, read live
every time the window redraws — not a preference of our own, so a change made in
System Settings or Task Manager shows up without a restart.

The third word is `Blocked`: registered, but switched off in the OS's own
startup list. Clicking that opens the list rather than re-registering, because
re-registering something already registered does nothing and would read as a
dead button.

## Core (pure, both platforms, tests first)

`LaunchAtLogin` in `VoiceKeyCore` / `VoiceKey.Core`:

- `LaunchAtLoginState` — `on` / `off` / `blocked`
- `LaunchAtLoginAction` — `enable` / `disable` / `openSettings`
- `label(title, state)` — the footer row's text; the title is the platform's own
  wording, the word after the dash is not
- `click(state)` — what a click asks for. `blocked` asks for the settings pane,
  never for a registration it already has.

Two cases each, ported case for case between the swift-testing and xUnit suites.

## Glue (per platform, not unit-testable)

**macOS — `Sources/VoiceKey/LoginItem.swift`.** `SMAppService.mainApp`:
`.enabled` → on, `.requiresApproval` → blocked, anything else → off.
`register()` / `unregister()`, and `SMAppService.openSystemSettingsLoginItems()`
for the blocked case. macOS 13+, and the app's floor is 14.

**Windows — `VoiceKey.App/LoginItem.cs`.** `HKCU\…\CurrentVersion\Run`, value
`VoiceKey`, the quoted path of `Environment.ProcessPath`. Blocked is
`…\Explorer\StartupApproved\Run`: when that key holds a value for us, an odd
first byte means the user disabled it in Task Manager — undocumented, but the
only signal there is, and the alternative is a row that says On over an app
that never starts. Enabling deletes that veto, because leaving it in place is
exactly the silent failure the row exists to avoid. `ms-settings:startupapps`
for the blocked case.

## Wiring

- `MainWindowModel` gains the state; `AppController` reads it live in `SyncUi` /
  `syncUI`, next to the grants it already reads live.
- The window actions protocol gains one entry, which performs `click(state)`.
- Both changelogs, and the file lists in `CLAUDE.md`.

## Verify

1. Core tests fail, then pass → `windows\test.ps1`, `macos/test.sh`.
2. Each platform builds → `windows\build.ps1`, `macos/build.sh`.
3. By hand: toggle on, sign out and in, VoiceKey is in the tray/menu bar.
   Disable it in Task Manager / System Settings, reopen the window, the row
   reads `Blocked`.
