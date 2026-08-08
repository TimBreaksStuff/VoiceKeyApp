# Changelog — VoiceKey for Windows

## 1.4.1 — the window's icon can be seen on a dark taskbar

**The window's icon was one fixed dark ink.** The tray glyph has always followed the taskbar's theme; the icon compiled into the executable could not, so on a dark taskbar the window's button was dark on dark. The window now draws its icon the same way the tray does, and re-reads the theme each time it opens.

- **The title bar keeps a dark icon**, since the window's own title bar stays light whatever the system theme says. Only the taskbar's copy follows the taskbar.

## 1.4.0 — you decide what ends the recording

**A pause is not always the end of a sentence.** VoiceKey stopped after a second of quiet, which is right for one dictated line and wrong for everything you have to think in the middle of. `Stop on silence — Off` in Settings hands that job to the shortcut instead: press Ctrl+Alt+D once to start, press it again when you are actually done.

- **The recording still ends after five minutes.** A shortcut can be forgotten, and a forgotten recording is a growing buffer and a transcript nobody wanted.
- **Silence stopping stays on unless you turn it off** — the same behaviour as before, in the same place as the sounds.
- **A click applies to the next recording, not the one in flight**, so it can never cut a sentence short.

**Hold-to-talk now takes a full second to count as a hold.** It was 0.35 s, which is a long press for a keyboard and a short one for a hand on a modifier chord — quick presses meant to toggle were being read as holds and ended the moment the key came up. Hold past a second and release still stops and types; anything shorter leaves the recording running until the next press.

## 1.3.0 — one place for the settings, and a way to get the next version

**The sidebar footer was five links deep.** Start with Windows, Sounds, Shortcut, Diagnostics log, Help — all of them equally loud, none of them things you touch more than once. They now live behind one row with a gear on it, and the card opens beside it the way Help always has: the window stays where it is, so a shortcut can be tried the moment it is changed.

- **The gear is drawn, not shipped** — eight teeth around a hollow hub on the same 16x16 grid the tray glyph uses.
- **Help hangs off the Settings row now**, since that is where its link lives.

**VoiceKey can update itself.** It asks GitHub once at launch whether there is a newer release. If there is, a clay `Update to 1.4.0` appears under Settings; clicking it downloads that release, and VoiceKey quits, swaps itself, and comes back.

- **A launch check that fails says nothing.** Nobody asked for it, so a missing network is not the user's problem. `Check for updates` inside Settings is the deliberate one, and that one reports what happened — `Update check failed — GitHub unreachable`.
- **The swap happens after VoiceKey is gone.** A running program cannot replace its own files, so the download is unpacked beside the install and a small script waits for the process to exit, copies the build in, and starts it again.
- **A release we cannot place is not an update.** Only a tag that reads as plain numbers counts, and only a `win-x64` zip is downloaded; anything else leaves the app saying it is up to date.
- The version VoiceKey is running is at the bottom of the Settings card.

## 1.2.0 — you can hear it listening

**Two short notes, one up and one down.** Starting a dictation plays E5 up to B5; stopping plays the same interval back down. Hold-to-talk used to be silent until the text appeared, which left the only confirmation that VoiceKey was recording in a tray icon nobody is looking at mid-sentence — the point of the shortcut is that you keep your eyes where they were.

- **The direction is the message.** Rising means listening, falling means done. Two notes of the same pair, so there is nothing to learn and no way to mistake one for the other after the first time.
- **Nothing is shipped to play.** The cues are synthesised as 16-bit mono PCM at 48 kHz in `CueSound`, the same way the tray glyph is drawn rather than loaded, and both notes fade to silence at either end so the waveform never steps — a step is a click.
- **The stop cue plays after the recorder has stopped**, so it can never end up inside the recording it is announcing.
- **`Sounds — On` in the sidebar footer turns them off**, beside `Start with Windows` and worded the same way. The choice is saved with the window's other preferences, and the cues are on until you say otherwise.

## 1.1.0 — start with Windows

**VoiceKey can start itself when you sign in.** A hold-to-talk shortcut that only exists after you remember to launch the app is not much of a shortcut. The sidebar footer carries the switch, under the rule with the other utility links: `Start with Windows — Off`. Clicking it toggles.

- **The word after the dash is what the system reports**, read fresh every time the window redraws — not a preference of our own. Turn the entry off in Task Manager and the row says so the next time you look, without a restart.
- **`Blocked` is its own word.** Task Manager's "Startup apps" switch does not remove the startup entry; it vetoes it, which used to be the shape of a setting that says On over an app that never starts. Clicking a blocked row opens Settings › Apps › Startup, and turning startup on from here drops an old veto rather than leaving it to bite.
- The entry is per-user (`HKCU`) and holds the path of the running executable, so nothing needs elevation. An entry that points somewhere else — the folder has been moved since — reads as `Off` rather than as a promise it can no longer keep; turning it on again writes the new path.

## 1.0.0 — first release

VoiceKey does what it set out to do on both platforms, from the same core, and the window has settled. Everything below 1.0 was getting there.

**The transcript row is finished**
- **Every action a row has is on the row.** The `···` overflow menu is gone, and with it the last invisible affordance in the window: a row is its time, its text, its word count, `Copy` and `Delete`.
- **Deleting takes two clicks.** The first turns the button into a filled clay "Delete again" and says so in a toast; the second acts, with the usual undo. The arming lapses after four seconds, so a forgotten one cannot lie in wait. The Delete key goes through the same two presses.
- **`Insert` is gone.** Re-inserting at the cursor hid the window first, so the app you came from could take focus back before the paste — which, with no easy way to reopen the window, read as a crash. The keyboard equivalent and the action behind them both go with it.
- **Word counts read as words**: "12 words", "1 word", "2,140 words", matching the day heading above them.

**VoiceKey no longer types into itself**
- Dictating while VoiceKey's own window is frontmost used to paste into whatever it had focused — its search field, or a Dictionary cell. Pasting into the search box filters the library down to the transcript just spoken, which looks exactly like losing everything. Nothing was ever lost, and clearing the search box brought it all back, but it should not happen at all. A dictation taken while VoiceKey is frontmost is now recorded and copied to the clipboard instead, and says so in the log. The rule is `DictationModes.InsertsAtCursor`, ported from the macOS 0.8.1 fix.

## 0.8.0 — the library comes first

The main window used to spend most of its area teaching the shortcut and showing three vanity figures, with one transcript row and 60% empty space below. The window is now the transcript library, and the teaching is a strip you can dismiss.

**The list**
- **Search** — a field in the header, Ctrl+F from anywhere in the window, Esc to clear. It filters across every day at once; a search that matches nothing says so instead of showing a blank page.
- **Sort** — "Newest first ▾" beside the first day's count: newest, oldest, or longest.
- **Row actions are visible at rest**: word count, `Copy`, `Insert`, and a `···` menu (copy, insert at cursor, add word to dictionary, delete). The old build revealed them on hover and made the whole row a copy target, which meant the affordance was invisible until you happened to point at it.
- **Confirmation lands on the row**: the word count becomes a green "Copied" for a beat, rather than a pill at the bottom of the window.
- **Keyboard**: ↑/↓ move between rows, Enter copies, Ctrl+Enter inserts, Delete deletes — with an undo in the toast, which puts the transcript back in its place, id and timestamp intact.
- Rows are one line at rest and open to two under the pointer or the keyboard. Below ~1100px of window width the trailing word counts step aside.
- **Empty state**: "Nothing dictated yet" with the shortcut, instead of a heading over nothing.

**Around the list**
- **Engine status is a pill** next to the page title — Ready / Listening… / Transcribing… / the error itself — coloured by state, with a dot that breathes while the microphone is open, and "· on-device" after it. Clicking it opens the granular state (`microphone · granted`, `model · loaded`) the old design showed inline; a missing grant is still a click through to Windows privacy settings.
- **The onboarding block is a strip**: keycap, one sentence, "Show me how", "Change shortcut", and a ✕. It retires itself after the third dictation, and a dismissal is remembered in the new `preferences.json`.
- **One weekly card in the sidebar** replaces the three header figures, with labels that mean something: words dictated, average pace, typing saved (measured against 40 wpm of typing, counting only runs that were timed). The weeks-streak and lifetime-words figures are gone.
- **Sidebar** carries the item counts — transcripts, dictionary entries — and the utility links moved into a footer under a rule: Shortcut, Diagnostics log, Help & shortcuts.
- **Help is a popup, not a dialog** — a card beside whatever asked for it: to the right of the sidebar link (bottom-aligned, so it grows up the sidebar rather than off the screen), under "Show me how" in the strip. It carries a "Change shortcut" button, so the walkthrough is somewhere you can act rather than only read. The modal `MessageBox` is gone, and with it `ShowWalkthrough` from `IMainWindowActions` — help is window behaviour, not something the app has to be asked for.
- **The shortcut capture window centres its text.** An empty preview line, which never had time to show anything before the window closed on the captured combo, was holding a third of the window and pushing both visible lines above centre.
- **A real status bar** replaces the floating delete button: what is stored and the promise that none of it is uploaded on the left, **Export all** (the whole log as a plain-text file, newest first under its timestamp) and "Delete all transcripts" on the right.
- The palette, type scale and spacing are the handoff's tokens throughout — Georgia, Segoe UI and Cascadia Mono standing in for Newsreader, Instrument Sans and JetBrains Mono. The tray glyph is unchanged.

**A shortcut that never bound no longer reports "Ready"**
- `RegisterHotKey` fails when another app already holds the combo, and the app said so — then the model finished loading a second later, set the state to idle, and wiped it. The pill went green over a dead shortcut. Every "nothing is happening" transition now goes through `DictationStatus.Settled`, so the error survives until the shortcut actually binds. "Retry" in the tray menu re-attempts the binding, and choosing a new shortcut clears that error and no other.

**Core**
- `TranscriptList` gains search, sort and per-row word counts, and no longer invents a heading for a day with nothing in it — an empty list is now the empty state's business.
- `TranscriptStats` is the weekly card: words, median pace, typing saved. Its streak and lifetime-word figures are gone with the header that showed them.
- `WindowPresentation` returns a `StatusPill` (label + tone + whether it leads anywhere) instead of a status word and a greeting, and decides when the onboarding strip has served its purpose.
- `TranscriptHistory` gains `Restoring()` for the undo and `ExportText()` for the export.

**Now on macOS too** — the redesign, the shortcut fix and the whole core are ported to the Mac build's 0.8.0, tests first. That port was written on Windows and has not been compiled; see `macos/CHANGELOG.md`.

**Not implemented from the handoff**: `Edit` and `Pin` in the row's overflow menu — neither has a drawn state anywhere in the mock, and both change what a transcript is rather than how it is shown. The comfortable/compact row-density setting has no surface to set it from. The custom 36px title bar is left to the real Windows chrome, which the handoff allows.

## 0.7.1 — delete every transcript at once

- **"Delete all transcripts"** in the Transcripts pane, a pill button pinned to the window's bottom right, over the list. It only appears when there is something to delete, and asks before it acts — this is the one action that cannot be undone, since clearing rewrites `history.json`. Cancelling leaves everything untouched. Both answers are recorded in the diagnostics log.
- **Click a transcript to copy it.** The whole row is the target, not just the hover "copy" button, and a small pill fades in at the bottom of the window to confirm — inside VoiceKey, not a Windows notification. The getting-started text says so.
- **No dotted focus rectangle** when a pane, table row or cell is clicked — WPF draws one by default, and it read as a rendering fault.
- **The getting-started block stays.** It used to retire itself after the first dictation, taking the shortcut reminder and the permission status with it; transcripts then appeared where it had been. Now it sits above the list permanently, and days of transcripts scroll below it.
- `TranscriptHistory` gains `Cleared()` and `IsEmpty`, so "delete everything" and "is there anything to delete" have names rather than being open-coded at each call site. The tray menu's existing "Clear History" now goes through the same method.

**Not on macOS yet** — the Mac build clears history from the menu only. The two cores have diverged by these two members until it is ported.

## 0.7.0 — first Windows release

Feature parity with the macOS 0.7.0 build, as a native .NET 9 / WPF tray app.

**Dictation**
- Global hotkey, default Ctrl+Alt+D: hold-to-talk (release inserts the text) and tap-to-toggle (<0.35s tap) on the same key. `RegisterHotKey` supplies the press and swallows the keystroke; a `WH_KEYBOARD_LL` hook supplies the release, which Win32 has no message for.
- Microphone capture through WASAPI at the device's native format, resampled to 16 kHz mono, with auto-stop after ~1s of trailing silence. Silence-only recordings are discarded before whisper runs, so it cannot hallucinate "Thank you."
- Transcription is fully local via Whisper.net (`ggml-small.en`), downloaded once into `%LOCALAPPDATA%\VoiceKey\models`. Backends are tried CUDA → Vulkan → CPU.
- Text is inserted by snapshotting the clipboard, writing the transcript, synthesizing Ctrl+V and restoring the snapshot. No permission grant is involved — but UIPI still blocks input aimed at an elevated app from a non-elevated VoiceKey.

**Window and tray**
- Tray icon with the keycap glyph, drawn with `System.Drawing` rather than shipped as PNGs: outlined when idle, solid while recording or transcribing, dimmed while the model loads and in the error state. It follows the taskbar's light/dark theme.
- Tray menu mirroring the Mac one: state header with the shortcut or elapsed time, Start/Stop, Copy Last Transcript, Recent submenu, All Transcripts…, Dictionary…, Shortcut…, Diagnostics Log, Quit.
- Main window with the 244px sidebar, header stats (weeks streak, lifetime words, median WPM) and two panes, on the same paper/ink palette as the Mac build. Each transcript row has `copy` and a `⋯` menu (copy, re-insert at cursor, add term to dictionary, delete).
- Dictionary pane: two editable tables over `VocabularyEditor`, saved after every committed edit, with shadowed rows greyed out.
- Shortcut capture window — any combo containing Ctrl, Alt or Win.

**Core**
- `VoiceKey.Core` ported from `VoiceKeyCore`, tests first: 148 xUnit cases mirroring the swift-testing suite. Behaviour is identical except where the platform differs — per-app modes key on the foreground process name rather than a bundle ID, and the window's status column has no accessibility line because Windows has no such grant.

**Storage** — `%LOCALAPPDATA%\VoiceKey\`: `dictionary.json`, `history.json`, `shortcut.json`, `models\`, `Logs\VoiceKey.log` (trimmed to ~1 MB, always at a line boundary).
