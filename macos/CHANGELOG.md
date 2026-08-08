# Changelog

## 1.4.0 — you decide what ends the recording

**A pause is not always the end of a sentence.** VoiceKey stopped after a second of quiet, which is right for one dictated line and wrong for everything you have to think in the middle of. `Stop on silence — Off` in Settings hands that job to the shortcut instead: press ⌃⌥D once to start, press it again when you are actually done.

- **The recording still ends after five minutes.** A shortcut can be forgotten, and a forgotten recording is a growing buffer and a transcript nobody wanted.
- **Silence stopping stays on unless you turn it off** — the same behaviour as before, in the same place as the sounds.
- **A click applies to the next recording, not the one in flight**, so it can never cut a sentence short.

**Hold-to-talk now takes a full second to count as a hold.** It was 0.35 s, which is a long press for a keyboard and a short one for a hand on a modifier chord — quick presses meant to toggle were being read as holds and ended the moment the key came up. Hold past a second and release still stops and pastes; anything shorter leaves the recording running until the next press.

## 1.3.0 — one place for the settings, and a way to get the next version

**The sidebar footer was five links deep.** Open at login, Sounds, Shortcut, Diagnostics log, Help — all of them equally loud, none of them things you touch more than once. They now live behind one row with a gear on it, and the card opens beside it the way Help always has: the window stays where it is, so a shortcut can be tried the moment it is changed.

- **The gear is drawn, not shipped** — eight teeth around a hollow hub on the same 16x16 grid the menu-bar glyph uses.
- **Help hangs off the Settings row now**, since that is where its link lives.

**VoiceKey can update itself.** It asks GitHub once at launch whether there is a newer release. If there is, a clay `Update to 1.4.0` appears under Settings; clicking it downloads that release, and VoiceKey quits, swaps itself, and comes back.

- **A launch check that fails says nothing.** Nobody asked for it, so a missing network is not the user's problem. `Check for updates` inside Settings is the deliberate one, and that one reports what happened — `Update check failed — GitHub unreachable`.
- **The swap happens after VoiceKey is gone.** A running program cannot replace its own files, so the download is unpacked beside the install and a small script waits for the process to exit, copies the new bundle over the old one, clears its quarantine flag, and opens it again.
- **A release we cannot place is not an update.** Only a tag that reads as plain numbers counts, and only a `macos-arm64` zip is downloaded; anything else leaves the app saying it is up to date.
- The version VoiceKey is running is at the bottom of the Settings card.

## 1.2.0 — you can hear it listening

**Two short notes, one up and one down.** Starting a dictation plays E5 up to B5; stopping plays the same interval back down. Hold-to-talk used to be silent until the text appeared, which left the only confirmation that VoiceKey was recording in a menu-bar icon nobody is looking at mid-sentence — the point of the shortcut is that you keep your eyes where they were.

- **The direction is the message.** Rising means listening, falling means done. Two notes of the same pair, so there is nothing to learn and no way to mistake one for the other after the first time.
- **Nothing is shipped to play.** The cues are synthesised as 16-bit mono PCM at 48 kHz in `CueSound`, the same way the menu-bar glyph is drawn rather than loaded, and both notes fade to silence at either end so the waveform never steps — a step is a click.
- **The stop cue plays after the recorder has stopped**, so it can never end up inside the recording it is announcing.
- **`Sounds — On` in the sidebar footer turns them off**, beside `Open at login` and worded the same way. The choice is saved, and the cues are on until you say otherwise.

## 1.1.0 — open at login

**VoiceKey can start itself when you log in.** A hold-to-talk shortcut that only exists after you remember to launch the app is not much of a shortcut. The sidebar footer carries the switch, under the rule with the other utility links: `Open at login — Off`. Clicking it toggles.

- **The word after the dash is what the system reports**, read fresh every time the window redraws — not a preference of our own. Turn the login item off in System Settings and the row says so the next time you look, without a restart.
- **`Blocked` is its own word.** Registered, but switched off in System Settings › General › Login Items — the one case where the app is in the list and still will not start. Clicking that opens the list rather than registering something already registered, which would have looked like a dead row.
- Registration is `SMAppService.mainApp`: no helper app, nothing installed, and it can be undone from System Settings as easily as from here.

## 1.0.0 — first release

VoiceKey does what it set out to do on both platforms, from the same core, and the window has settled. Everything below 1.0 was getting there.

**The transcript row is finished**
- **Every action a row has is on the row.** The `···` overflow menu is gone, and with it the last invisible affordance in the window: a row is its time, its text, its word count, `Copy` and `Delete`.
- **Deleting takes two clicks.** The first turns the button into a filled clay "Delete again" and says so in a toast; the second acts, with the usual undo. The arming lapses after four seconds, so a forgotten one cannot lie in wait. The Delete key goes through the same two presses.
- **`Insert` is gone.** Re-inserting at the cursor hid the window first, so the app you came from could take focus back before the paste — which, with no easy way to reopen the window, read as a crash. The keyboard equivalent and the action behind them both go with it. The 0.8.1 note below is superseded by this: there is no Insert button left to be unaffected.
- **Word counts read as words**: "12 words", "1 word", "2,140 words", matching the day heading above them.

## 0.8.1 — dictating with the window open

**Dictating while VoiceKey's own window was in front made the library look empty.** The transcript was pasted at the cursor, as always — but the cursor was in VoiceKey's search field, so the list filtered itself down to the one transcript just spoken and every earlier one vanished. Nothing was ever lost: the file was intact, and clearing the search box brought them all back. It only showed on macOS, where the search field takes focus when the window opens.

VoiceKey no longer types into itself. A dictation taken while it is the frontmost app is recorded and copied to the clipboard instead, and says so in the log. The row's own "Insert" button is unaffected — it already stepped the app aside before pasting.

## 0.8.0 — the library comes first

The Windows 0.8.0 redesign, ported. The window used to spend most of its area teaching the shortcut and showing three vanity figures; it is now the transcript library, and the teaching is a strip you can dismiss.

**The list**
- **Search** — a field in the header, ⌘F from anywhere in the window, Esc to clear. It filters across every day at once; a search that matches nothing says so instead of showing a blank page.
- **Sort** — "Newest first ▾" beside the first day's count: newest, oldest, or longest.
- **Row actions are visible at rest**: word count, `Copy`, `Insert`, and a `···` menu (copy, insert at cursor, add word to dictionary, delete). The old build revealed them on hover, which left the affordance invisible until you happened to point at a row.
- **Confirmation lands on the row**: the word count becomes a green "Copied" for a beat.
- **Keyboard**: ↑/↓ move between rows, Return copies, ⌘Return inserts, Delete deletes — with an undo in the toast, which puts the transcript back in its place, id and timestamp intact.
- **Empty state**: "Nothing dictated yet" with the shortcut, instead of a heading over nothing. A day with no transcripts no longer gets a heading at all.

**Around the list**
- **Engine status is a pill** next to the page title — Ready / Listening… / Transcribing… / the error itself — coloured by state, with a dot that breathes while the microphone is open, and "· on-device" after it. Clicking it opens the granular state (`microphone · granted`, `accessibility · granted`, `model · loaded`) the old design showed inline; a missing grant is still a click through to the matching Privacy pane.
- **The onboarding block is a strip**: keycap, one sentence, "Show me how", "Change shortcut", and a ✕. It retires itself after the third dictation, and a dismissal is remembered (`hasDismissedOnboarding`).
- **Help is a popover, not a modal alert** — a card beside whatever asked for it: to the right of the sidebar link, under "Show me how" in the strip. It carries a "Change shortcut" button, so the walkthrough is somewhere you can act rather than only read.
- **One weekly card in the sidebar** replaces the three header figures, with labels that mean something: words dictated, average pace, typing saved (measured against 40 wpm of typing, counting only runs that were timed). The weeks-streak and lifetime-words figures are gone, and so is the "Welcome back" greeting.
- **Sidebar** carries the item counts — transcripts, dictionary entries — and the utility links moved into a footer under a rule: Shortcut, Diagnostics log, Help & shortcuts.
- **A real status bar**: what is stored and the promise that none of it is uploaded on the left, **Export all** (the whole log as a plain-text file, newest first under its timestamp) and "Delete all transcripts" on the right. Deleting everything asks first.
- The palette, type scale and spacing are the handoff's tokens throughout. The menu-bar glyph is unchanged.

**A shortcut that never bound no longer reports "Ready"**
- `RegisterEventHotKey` can fail — another app already holds the combo — and the app said so, then the model finished loading a second later and set the state back to idle, wiping it. Every "nothing is happening" transition now goes through `DictationStatus.settled(shortcutIsBound:shortcut:)`, so the error survives until the shortcut actually binds. "Retry" in the menu re-attempts the binding, and choosing a new shortcut clears that error and no other. `HotKey` reports `isRegistered` for the first time.

**Core**
- `TranscriptList` gains search, sort, per-row word counts and the status bar's storage line; `TranscriptStats` is the weekly card; `WindowPresentation` returns a `StatusPill` and decides when the onboarding strip has served its purpose; `TranscriptHistory` gains `restoring()`, `cleared()`, `isEmpty` and `exportText()`. The suites are the xUnit ones ported back, case for case — the two cores are level again.

**Built on macOS.** The port was written without a Mac to compile it; what it took to make it run:
- `TranscriptStats.grouped` was internal to VoiceKeyCore and called from the window — the only compile error.
- **The list sat against the right edge of the pane**, about a third of its width. A stack's `.width` alignment only makes its arranged views equal to *each other*, never to the stack, so the list shrank to its widest transcript. Every band is pinned to the pane's width explicitly now, as the dictionary's already were.
- **A row's actions sat beside its text instead of at the edge.** The text's trailing edge is pinned to the action stack and the stack's to the row, and an `NSStackView` hugs its content at `.defaultLow` where a label hugs at `.defaultHigh` — so the stack took the slack, stretched, and packed its buttons at its leading edge. It hugs at `.required` now, and the text column takes the slack. Same fix in the onboarding strip, which is pinned the same way.
- **The header cleared the traffic lights.** A full-size content view starts under them, and only the sidebar knew: the page title sat 25pt above the "VoiceKey" beside it, and the top of the search field and status pill fell in the titlebar's drag region, where a click moves the window. Both bands hang off one titlebar constant now, keeping the 22pt offset they have on Windows.
- The time column is 78pt wide with the text starting where it ends, not a 78pt label with a further 24pt gap after it.

**Not implemented from the handoff**: `Edit` and `Pin` in the row's overflow menu — neither has a drawn state in the mock. Row text stays one line here rather than opening to two on hover, and the row-density setting has no surface to set it from.

## 0.7.0 — 2026-08-05

Main window — implements `handoff-window/WINDOW-SPEC.md`.

- Opening the app (double-click, or menu → "All Transcripts…") now opens a window: a 244pt sidebar over a fixed header and a scrolling transcript list. VoiceKey stays a menu-bar app (`LSUIElement`) — no Dock icon, no app name in the menu bar.
- **Double-clicking the menu-bar icon opens the window.** A single click still opens the menu, but has to wait out the double-click interval (capped at 0.3s) first; a right- or ⌃-click opens the menu straight away.
- Transcripts are grouped by day, newest first ("Today", "Yesterday", then the date), each row showing its time, the text verbatim with its paragraphs, and — on hover — `copy` and a `⋯` menu (Copy, Re-insert at Cursor, Add Term to Dictionary, Delete). A day with nothing in it keeps its heading and says so.
- Header stats derived from local history alone: consecutive weeks with a dictation, lifetime words (`23.4K` from ten thousand up), and median words-per-minute over the last 30 timed runs. A stat with no data hides its column rather than showing a zero.
- **History is now persisted** to `~/Library/Application Support/VoiceKey/history.json` (text, timestamp, recording duration; capped at 2000). It was in-memory only before — the list and the stats need it to survive a relaunch. "Clear History" and per-row Delete rewrite the file.
- Getting-started block until the first successful dictation: the shortcut as an inline keycap, the live status word, and a `microphone · granted` permission list where anything missing darkens and opens the matching Privacy pane. "Show me how" (and sidebar → Help) explains the flow; "Change shortcut" opens the capture panel. The greeting is "Welcome back" with no name — there is nowhere to set one yet — and the sidebar has no Settings row for the same reason.
- The dictionary moved into the window as the `02 Dictionary` pane — the standalone dictionary window is gone. Menu → "Dictionary…" opens the window on that pane, and "Add Term to Dictionary" from a transcript switches to it with the term already typed in when the phrase is short enough to be one.
- Header alignment: the 30/44/20 padding is set by constraints instead of a stack's edge insets (a stack gives its insets up first when anything squeezes it, which flattened the header), the stat captions sit on the greeting's baseline, and each hairline spans its columns. The transcript list forces overlay scrollers, so a system set to always-visible scroll bars no longer pulls the list 15pt off the header's grid. Tracked labels no longer carry a trailing letter-space, which had nudged every right-aligned one off true.
- Type and palette follow the spec, with the system serif (New York) and monospaced faces standing in for Source Serif 4 / IBM Plex Mono, so nothing is bundled. Light only, as specified — the window forces `.aqua`.
- The app now installs a minimal main menu (Edit, Close, Quit): agent apps never display a menu bar, but without one Cmd+C/V do not work in the window's fields.

## 0.6.0 — 2026-08-05

- Dictionary screen: menu → "Dictionary…" opens a real window instead of `dictionary.json` in a text editor. Replacements are a two-column table — the spoken phrase on the left, the text VoiceKey types on the right — and vocabulary terms are a second table below it. `+`/`−` add and remove rows; every edit is written to disk immediately, so the next dictation picks it up.
- A row shadowed by an earlier row with the same spoken phrase is greyed out and says so in its tooltip, instead of silently losing to it in the JSON map.
- Half-typed rows and blank terms stay visible while you edit but are never saved as rules, and surrounding whitespace is trimmed.
- The JSON file is unchanged and still hand-editable; the window re-reads it every time it opens.

## 0.5.0 — 2026-08-05

Design pass — icon, glyph and menu follow the "Keycap & rules" handoff.

- New menu-bar glyph: an outlined keycap with two rules, solid while recording or transcribing, dimmed while the model loads and in the error state. Drawn as vectors (`MenuBarGlyph.swift`) instead of shipped PNGs — sharp at every scale — and a template image, so macOS owns the light/dark and highlighted appearance.
- New app icon (`Resources/AppIcon.iconset` → `AppIcon.icns`, assembled by `build.sh`).
- Menu restructured: a header row that names the state on the left and its detail on the right — the shortcut when idle, a ticking `m:ss` while recording, the model while transcribing — then the dictation actions, a "Transcripts" section (Recent, Dictionary) and a "Setup" section (Shortcut…, Diagnostics Log).
- "Copy Last Transcript" (⇧⌘V) copies the newest transcript without opening a submenu; disabled while the history is empty.
- "Diagnostics Log" opens `~/Library/Logs/VoiceKey.log` — previously documented but unreachable from the app.
- "Dictionary" is now a submenu: open `dictionary.json` or reveal it in Finder.
- Error state: the menu leads with "Open Privacy Settings…", which opens the Microphone or Accessibility pane depending on which grant is actually missing. A transcript that only reached the clipboard now enters that state instead of quietly rewriting the status line.
- Renames: "History" → "Recent", "Change Shortcut…" → "Shortcut…", "Edit Dictionary…" → "Dictionary".
- The diagnostics log no longer grows without bound: at launch, anything past ~1 MB is cut back to the most recent 500 KB (on a line boundary).

## 0.4.0 — 2026-08-05

- Custom dictionary: menu → "Edit Dictionary…" opens `~/Library/Application Support/VoiceKey/dictionary.json` (created from a documented template on first use). `terms` bias Whisper toward your vocabulary via an initial prompt (client names, API names, jargon); `replacements` rewrite what Whisper still gets wrong ("get hub" → "GitHub", case-insensitive whole-phrase, regex-safe, longest key wins). Reloaded on every dictation — no restart needed.
- Transcript cleanup: filler words ("um", "uh", "er", …) are removed — a filler opening a sentence hands its capital to the next word — and immediate stutter repetitions collapse ("the the report" → "the report"). Repeats across punctuation ("No, no, never.") are kept.
- Per-app modes: the transcript is formatted for the app it lands in. Terminals/editors/IDEs (Terminal, iTerm2, Ghostty, VS Code, Cursor, Xcode, JetBrains, Zed, Sublime) get code mode — no trailing period. Mail clients (Mail, Outlook, Spark, Superhuman) get email mode — a terminal period is ensured. Everything else is untouched.
- History: menu → "History" lists the last 10 transcripts (newest first, in-memory only — cleared on quit); click one to copy it back to the clipboard. "Clear History" wipes it.
- Testing infrastructure: new `VoiceKeyCore` library target holds all pure logic (cleaner, dictionary, modes, history) with a swift-testing suite in `Tests/VoiceKeyCoreTests`; `./test.sh` runs it with CommandLineTools alone (no Xcode needed — the script supplies the Testing.framework search/plugin paths SwiftPM doesn't add itself).

## 0.3.0 — 2026-08-05

- Configurable shortcut: menu → "Change Shortcut…" opens a small capture panel; press any combo with ⌘/⌃/⌥ and it takes effect immediately (persisted in UserDefaults). Default stays ⌃⌥D.
- Stable code signing: `build.sh` now signs with the self-signed "VoiceKey Dev" certificate (login keychain), so Accessibility/Microphone grants survive rebuilds — this was the root cause of "it does not write the text": every ad-hoc rebuild invalidated the grant, and pasting silently fell back to the clipboard.
- Non-speech whisper annotations ("[wind howling]", "(music)") are discarded instead of pasted.
- Verified end-to-end by machine: synthetic ⌃⌥D + spoken TTS through the speakers → transcript pasted into a TextEdit document.

## 0.2.0 — 2026-08-05

- Hold-to-talk: hold ⌃⌥D, speak, release — text is inserted on release. A quick tap (<0.35s) still toggles as before. Same key, both behaviors.
- File logging to `~/Library/Logs/VoiceKey.log` (permission state, hotkey events, sample counts, transcripts, errors) — the unified log redacts NSLog output as `<private>`, which made "it doesn't work" undiagnosable.

## 0.1.0 — 2026-08-05

Initial version.

- Menu-bar-only app (no Dock icon); the status icon is the whole UI.
- Global toggle hotkey ⌃⌥D (Carbon `RegisterEventHotKey`): press to record, press again to stop — or auto-stop after ~1s of trailing silence.
- Local transcription via WhisperKit, `openai_whisper-small.en`, model cached in `~/Library/Application Support/VoiceKey/`.
- Inserts the transcript at the cursor of the frontmost app (pasteboard snapshot → synthetic Cmd+V → pasteboard restore). Falls back to clipboard + menu hint when Accessibility is not granted.
- Silence-only recordings are discarded without invoking whisper (avoids the "Thank you." hallucination).
- CLI-only build: `swift build` + hand-assembled `.app` bundle in `build.sh`, ad-hoc signed.
