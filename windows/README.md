# VoiceKey for Windows

Minimal Windows tray dictation app. **Hold Ctrl+Alt+D**, speak, release — the transcribed text is typed at the cursor of whatever app has focus. A quick tap (<0.35s) toggles instead: tap to start, tap again to stop (or just stop talking for ~1s and it auto-stops). Change the shortcut via tray icon → right-click → "Shortcut…" — press any combo containing Ctrl, Alt or Win. Transcription runs fully local via [Whisper.net](https://github.com/sandrohanea/whisper.net) (whisper.cpp on CUDA), model `ggml-small.en`.

Left-clicking the tray icon, or the menu's "All Transcripts…", opens the main window: everything you have dictated, grouped by day, searchable and sortable, with `Copy` and `Delete` on each row; the sidebar switches to the dictionary. Closing the window leaves VoiceKey running in the tray. History lives in `%LOCALAPPDATA%\VoiceKey\history.json`.

The gear at the bottom of the sidebar opens **Settings**: `Start with Windows`, `Sounds`, `Shortcut`, the diagnostics log, the walkthrough, and the update check. Starting and stopping a dictation plays two short notes — E5 up to B5, then back down — which `Sounds — On` turns off; the choice is kept in `%LOCALAPPDATA%\VoiceKey\preferences.json`.

**Updates**: VoiceKey asks GitHub for the latest release once at launch, and says nothing if that fails. When there is a newer one, a clay `Update to …` appears under Settings; clicking it downloads the `win-x64` zip, quits, copies the build over this one, and starts it again.

## Build & run

```powershell
.\build.ps1          # publish a self-contained build into publish\
.\build.ps1 -Run     # same, then launch
.\test.ps1           # run the VoiceKey.Core suite

dotnet run --project VoiceKey.App    # debug build, straight from source
```

Requires: Windows 10 1809+ (x64), [.NET 9 SDK](https://dotnet.microsoft.com/download) (`winget install Microsoft.DotNet.SDK.9`). An NVIDIA GPU is used when present; without one, whisper.cpp falls back to the CPU automatically.

## First launch

1. The tray icon is dimmed while the model (~470MB) downloads into `%LOCALAPPDATA%\VoiceKey\models` — one time only.
2. If **Settings → Privacy & security → Microphone → Let desktop apps access your microphone** is off, recording fails; the menu says so and links to the page.

No accessibility permission is needed — `SendInput` requires none. The one exception is a target app running **as administrator** while VoiceKey is not: UIPI blocks synthetic input into it, and the paste silently does nothing. Run VoiceKey elevated too if you dictate into elevated windows.

Icon states: the keycap glyph is outlined when idle and solid while recording or transcribing; it dims while the model loads and in the error state. Right-click the icon — the header names the state and shows the shortcut, the elapsed recording time, or the error message.

Diagnostics: menu → "Diagnostics Log", or `%LOCALAPPDATA%\VoiceKey\Logs\VoiceKey.log` (every hotkey press, recording, transcript and failure).

## Layout

```
VoiceKey.Core/        # pure logic — no WPF, no whisper. Mirrors macos/Sources/VoiceKeyCore
VoiceKey.Core.Tests/  # xUnit, ported case for case from the swift-testing suite
VoiceKey.App/         # WPF tray app: hotkey, WASAPI capture, Whisper.net, SendInput
```

## Changing model / language

Both live in `VoiceKey.App/Transcriber.cs`: `ModelType` and `Language`. For multilingual dictation switch to e.g. `GgmlType.LargeV3Turbo` and set the language (or remove the option for auto-detect).

## Differences from the macOS build

- **No accessibility grant.** macOS needs one for the synthetic Cmd+V; Windows does not.
- **Tray clicks follow the Windows convention**: left click opens the window, right click opens the menu. The Mac build uses one click for the menu and two for the window.
- **Per-app modes** key on the foreground process name (`Code.exe`, `OUTLOOK.EXE`) rather than a bundle ID — see `VoiceKey.Core/DictationMode.cs`.
- **Storage** is `%LOCALAPPDATA%\VoiceKey\` rather than `~/Library/Application Support/VoiceKey/`, with the same file names. The two builds' `history.json` files are not interchangeable — dates are ISO-8601 strings here, Core Data reference-date doubles there.
