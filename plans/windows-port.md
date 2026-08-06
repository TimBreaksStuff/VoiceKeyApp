# Windows port — plan

VoiceKey ships as two native apps from one repository: the existing Swift/AppKit
menu-bar app for macOS, and a new C#/WPF tray app for Windows. Feature parity
with macOS 0.7.0 is the target for the first Windows release.

## Decisions

| | |
|---|---|
| Stack | .NET 9, C#, WPF (`net9.0-windows`) |
| Transcription | [Whisper.net](https://github.com/sandrohanea/whisper.net) (whisper.cpp), CUDA runtime, `ggml-small.en` |
| Audio | NAudio / WASAPI capture, resampled to 16 kHz mono float |
| Hotkey | `RegisterHotKey` for press + low-level keyboard hook for release |
| Insertion | Clipboard snapshot → `SendInput` Ctrl+V → restore |
| Tray | `NotifyIcon` with a drawn keycap glyph, no raster assets |
| Layout | `macos/` and `windows/` side by side; shared docs at the root |

The two cores are deliberately duplicated rather than shared: no runtime spans
Swift-on-Apple-Silicon and .NET-on-Windows without dragging an FFI boundary
through the one part of the app that is pure, fast and fully tested. The
duplication is kept honest by porting the *tests* first — the C# suite asserts
the same behaviours, case for case, as the swift-testing suite.

## Layout

```
macos/                        # the existing Swift app, unchanged
windows/
  VoiceKey.sln
  VoiceKey.Core/              # pure logic, no WPF, no whisper — mirrors VoiceKeyCore
  VoiceKey.Core.Tests/        # xUnit — ported from Tests/VoiceKeyCoreTests
  VoiceKey.App/               # WPF tray app, WASAPI, SendInput, Whisper.net
plans/
```

## Core port map

Every file below is pure `Foundation` today and becomes pure BCL C#. Behaviour
is identical unless the note says otherwise.

| Swift (`macos/Sources/VoiceKeyCore`) | C# (`windows/VoiceKey.Core`) | Notes |
|---|---|---|
| `TranscriptCleaner.swift` | `TranscriptCleaner.cs` | `NSRegularExpression` → `System.Text.RegularExpressions`; the case-insensitive backreference that forced the Swift workaround works natively in .NET |
| `VocabularyDictionary.swift` | `VocabularyDictionary.cs` | `Codable` → `System.Text.Json`; combined-alternation matcher ports directly |
| `VocabularyEditor.swift` | `VocabularyEditor.cs` | `IndexSet` → `IReadOnlySet<int>` |
| `DictationMode.swift` | `DictationMode.cs` | **Behaviour change**: bundle IDs → process executable names (`code.exe`, `windowsterminal.exe`, `outlook.exe`, …) |
| `TranscriptHistory.swift` | `TranscriptHistory.cs` | `TimeInterval` → `TimeSpan`; same 10/2000 limits |
| `TranscriptList.swift` | `TranscriptList.cs` | `DateFormatter` + `en_US_POSIX` → `CultureInfo.InvariantCulture` |
| `TranscriptStats.swift` | `TranscriptStats.cs` | week streak via `ISOWeek`; same hand-rolled digit grouping |
| `StatusPresentation.swift` | `StatusPresentation.cs` | shortcut string is the only Windows-flavoured value (`Ctrl+Alt+D`) |
| `WindowPresentation.swift` | `WindowPresentation.cs` | **Behaviour change**: no accessibility grant on Windows — the third line becomes microphone / model only |

## App layer

| Swift (`macos/Sources/VoiceKey`) | C# (`windows/VoiceKey.App`) | Mechanism |
|---|---|---|
| `HotKey.swift` (Carbon) | `HotKey.cs` | `RegisterHotKey` gives the press; a `WH_KEYBOARD_LL` hook gives the release that hold-to-talk needs |
| `AudioRecorder.swift` (AVAudioEngine) | `AudioRecorder.cs` | `WasapiCapture` → `MediaFoundationResampler` → 16 kHz mono; same RMS threshold and 1 s trailing-silence auto-stop |
| `Transcriber.swift` (WhisperKit) | `Transcriber.cs` | Whisper.net + `Whisper.net.Runtime.Cuda`; model downloaded once to `%LOCALAPPDATA%\VoiceKey\models` |
| `TextInserter.swift` (Cmd+V) | `TextInserter.cs` | clipboard snapshot → `SendInput` Ctrl+V → restore after 700 ms |
| `Log.swift` | `Log.cs` | `%LOCALAPPDATA%\VoiceKey\Logs\VoiceKey.log` |
| `MenuBarGlyph.swift` | `TrayGlyph.cs` | keycap drawn with `System.Drawing`, outlined idle / solid recording |
| `AppController.swift` | `AppController.cs` | same state machine, same transcript pipeline |
| `MainWindowController.swift` + panes | `MainWindow.xaml` + panes | same 244 pt sidebar, header, two panes |
| `Theme.swift` | `Theme.xaml` | same paper/ink palette; Georgia/Cascadia Mono stand in for New York/SF Mono |
| `ShortcutCapture.swift` | `ShortcutWindow.xaml` | same rule: the combo must contain Ctrl, Alt or Win |

## Platform differences worth stating

- **No TCC.** Windows has no accessibility grant — `SendInput` just works. The
  microphone is a Settings toggle, not a prompt, so a denied mic surfaces as a
  capture failure rather than a permission callback.
- **Storage** moves from `~/Library/Application Support/VoiceKey/` to
  `%LOCALAPPDATA%\VoiceKey\`, same file names (`dictionary.json`, `history.json`).
- **Default shortcut** is Ctrl+Alt+D, matching ⌃⌥D key-for-key.
- **No `LSUIElement`.** The WPF app starts with no window shown and no taskbar
  button; the tray icon is the whole UI until the window is opened.

## Increments

Each leaves the tree building and the suite green.

1. Repo restructure → verify: `macos/build.sh` and `macos/test.sh` still work from their new location.
2. Solution scaffold → verify: `dotnet build` and `dotnet test` succeed on an empty core.
3. Core port, one type per increment, tests first → verify: `dotnet test` green, case count matching the Swift suite.
4. Platform glue, thin and manually verified → verify: hotkey logs a press/release pair; a recording produces samples; a transcript reaches the clipboard.
5. Tray app and state machine → verify: hold Ctrl+Alt+D, speak, release, text lands at the cursor.
6. Main window and dictionary pane → verify: history persists across a relaunch; dictionary edits change a subsequent transcript.
