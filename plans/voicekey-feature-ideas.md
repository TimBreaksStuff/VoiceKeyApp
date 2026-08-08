# VoiceKey — Feature Ideas from Competitor Research (2026-08-05)

Researched: Wispr Flow, Superwhisper, VoiceInk (open-source, closest architecture to
VoiceKey), Aqua Voice, MacWhisper, Willow, Talon/Cursorless. Ideas filtered for the two
target workflows — **coding** and **business emails** — and for VoiceKey's constraints:
local-first, minimal, SwiftPM, testable logic behind thin system seams.

## Priority 1 — highest impact, fully local, TDD-friendly

### 1. Custom dictionary / vocabulary biasing
Every competitor has this; it's the single biggest accuracy lever for both target uses
(API names, product names, client names, jargon).
- Feed user terms to Whisper as an initial prompt (WhisperKit `promptTokens` /
  `usePrefillPrompt`) so recognition is biased toward them.
- Post-transcription replacement rules for the stubborn cases ("get hub" → "GitHub",
  "jason" → "JSON", client-name spellings).
- Store as a simple JSON/plist in Application Support; "Edit Dictionary…" menu item.
- Replacement engine is a pure function → test-first.

### 2. Transcript cleanup pipeline (filler words, stumbles)
Wispr Flow's headline feature. Strip "um/uh/er", collapse immediate word repetitions
("the the"), trim leading/trailing artifacts. Extends the existing non-speech-annotation
filter in a pure, testable pipeline stage.

### 3. Spoken formatting commands
Deterministic (no LLM): "new line", "new paragraph", "bullet point", "quote/unquote",
"comma/period" when spoken as commands. Standard in Willow/Speechify-class apps and
cheap to implement as another pure pipeline stage.

### 4. Per-app modes (VoiceInk "Power Mode")
Detect the frontmost app (`NSWorkspace.shared.frontmostApplication`) at insert time and
apply a mode:
- **Code mode** (Terminal, VS Code, Cursor, Xcode, Ghostty…): no trailing period, keep
  casing literal, technical vocabulary prompt.
- **Email mode** (Mail, Outlook, browser+Gmail): sentence capitalization, paragraph
  breaks, no-filler, formal punctuation.
- **Default mode**: current behavior.
Mode selection logic = pure function of bundle ID → testable. Config in UserDefaults.

### 5. Transcription history
Menu shows last N transcripts; click to copy. Rescues the "pasted into the wrong
window" case and the clipboard-fallback case. Local file, "Clear History" item.

## Priority 2 — differentiators

### 6. Optional AI polish layer (email tone) — keep it on-device
Superwhisper/Wispr route output through an LLM for tone ("email-ready in Gmail, casual
in Slack"). VoiceKey can do this without breaking the local-only promise via the Apple
Foundation Models framework (on-device, macOS 26+), with per-mode prompts:
"Polish into a professional email", "Tighten into a commit message". Off by default;
graceful no-op below macOS 26.

### 7. Voice snippets
Speak a cue phrase → paste a canned block (signature, scheduling link, boilerplate
reply, code license header). Wispr Flow's "snippet library". Pure lookup stage in the
pipeline; snippets editable via a small settings file/menu.

### 8. Latency: streaming preview + model picker
Aqua Voice wins reviews on sub-500ms perceived latency. Locally:
- Small floating HUD showing live partial transcript while recording (WhisperKit
  supports streaming) — perceived latency drops massively.
- Menu item to pick model (`small.en` ↔ `distil-whisper` / `large-v3-turbo`) trading
  speed vs. accuracy; turbo models are much faster on ANE.

### 9. Recording UX polish
- **Esc cancels** a recording without transcribing/pasting.
- Subtle start/stop sounds (configurable) so hold-to-talk state is unambiguous.
- Menu-bar tooltip shows current mode + shortcut.

### 10. German / multilingual toggle
Business email context likely includes German. Offer a language menu backed by a
multilingual model (`small` / `large-v3-turbo`) with auto-detect, instead of the
hard-coded `small.en`.

## Priority 3 — later / bigger bets

### 11. Command mode (rewrite selection by voice)
Wispr Flow paid tier: select text, hold hotkey, say "make this more concise" → replaced
in place. Needs the LLM layer (idea 6) plus read-selection via Accessibility. Powerful
for email editing; do after 6.

### 12. Typing fallback for paste-hostile apps
Some apps/fields block Cmd+V (secure fields, some terminals/VMs). Fall back to CGEvent
keystroke synthesis per character when paste fails.

### 13. Screen-context awareness
Aqua Voice reads the active screen to pick terminology/tone. Heavy and
privacy-sensitive; only worth it after per-app modes prove insufficient.

## Explicitly not pursuing
- Full voice *control* of the computer (Talon/Cursorless territory — different product).
- Cloud STT engines — against the local-only premise.
- Cross-device sync — no fleet, no account system.

## Sources
- https://tldv.io/blog/wisprflow/ · https://droidcrunch.com/wispr-flow-review/ (Wispr Flow: cleanup, dictionary, snippets, command mode)
- https://superwhisper.com/ · https://max-productive.ai/ai-tools/superwhisper/ (Superwhisper: custom modes, vocabulary w/ replacements, LLM formatting)
- https://tryvoiceink.com/ · https://metawhisp.com/blog/voice-ink-review/ (VoiceInk: Power Mode per-app settings, open-source Swift + whisper.cpp)
- https://spokenly.app/blog/aqua-voice-review (Aqua Voice: streaming latency, screen context)
- https://willowvoice.com/blog/best-voice-to-text-email-tools-2025 (email-focused tone/formatting features)
- https://www.yaps.ai/blog/talon-voice-alternative · https://www.joshwcomeau.com/blog/hands-free-coding/ (voice-coding landscape)
