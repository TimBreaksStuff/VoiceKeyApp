# Plan — VoiceKey main window (0.7.0)

Implements `handoff-window/WINDOW-SPEC.md`: a single window with a 244pt sidebar
and a scrolling, day-grouped transcript list, opened on launch and on re-open
(double-click) of the still-running menu-bar app.

## Decisions taken with the user

| question | decision |
|----------|----------|
| History for the list + stats | Persist transcripts (text, date, duration) to `~/Library/Application Support/VoiceKey/history.json` |
| Fonts | System fonts — New York (serif design) + monospaced system font, not bundled Source Serif 4 / IBM Plex Mono |
| Dictionary | Moves *into* the window as the `02 Dictionary` pane; the standalone dictionary window goes away |
| Launch style | Stays `LSUIElement` — no Dock icon, no app name in the menu bar |

Unspecified bits decided here: `Show me how` and `Help` open the same short
walkthrough sheet; `Settings` opens the shortcut capture; the light palette is
fixed (window forces `.aqua`, dark mode is out of scope per the spec).

## VoiceKeyCore (test-first)

1. `Transcript` — text, date, duration, id; `wordCount`.
2. `TranscriptHistory` — now holds `[Transcript]` (newest first, capped 2000),
   `entries` stays the newest 10 texts for the menu; `removing(id:)`;
   `load(from:)` / `save(to:)` JSON, mirroring `VocabularyDictionary`.
3. `TranscriptStats` — weeks streak, lifetime words (K-abbreviated ≥10k),
   median WPM over the last 30 timed runs. Each value optional → hide column.
4. `TranscriptList` — day groups (Today / Yesterday / "5 August"), per-group
   count line, per-row time label.
5. `WindowPresentation` — header date line, greeting from a full name,
   permission lines (`microphone · granted`, …) with an attention flag.

## AppKit

- `Theme.swift` — palette + serif/mono font helpers.
- `MainWindowController.swift` — window, sidebar, header, pane switching.
- `TranscriptListView.swift` — hint block, group headings, hover rows, row menu.
- `DictionaryPane` — `DictionaryWindowController` refactored to vend an
  `NSView`; the main window embeds it.
- `AppController` — owns the window, persists history, feeds status/permissions
  to the window, opens it on launch and on `applicationShouldHandleReopen`.
- Minimal `NSApp.mainMenu` (Edit + Close) so Cmd+C/V/W work in the window; no
  named app menu (agent apps do not display a menu bar).
