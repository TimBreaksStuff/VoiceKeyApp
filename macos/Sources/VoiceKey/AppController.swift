import AppKit
import AVFoundation
import Carbon.HIToolbox
import UniformTypeIdentifiers
import VoiceKeyCore

final class AppController: NSObject, NSApplicationDelegate {
    private enum State { case loading, idle, recording, transcribing, error(String) }

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var pendingMenuPopUp: DispatchWorkItem?
    private var headerItem: NSMenuItem!
    private var privacyItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var copyLastItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var hotKey: HotKey?
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private var state: State = .loading { didSet { syncTimer(); syncUI() } }
    private var history = TranscriptHistory()

    // Hold-to-talk: a press that starts recording remembers when; if the key
    // is released after this threshold it was a hold — stop and insert.
    // A quicker tap leaves recording running (toggle mode).
    private var recordingStartedByPressAt: Date?
    private let holdThreshold: TimeInterval = 1

    // Drives the ticking elapsed time in the menu header while recording.
    private var recordingStartedAt: Date?
    private var tickTimer: Timer?

    private let capture = ShortcutCapture()
    private var shortcutLabel: String {
        UserDefaults.standard.string(forKey: "hotKeyLabel") ?? "⌃⌥D"
    }

    private static func supportURL(_ file: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceKey/\(file)")
    }

    private static var dictionaryURL: URL { supportURL("dictionary.json") }
    private static var historyURL: URL { supportURL("history.json") }

    private lazy var dictionaryPane = DictionaryPane(url: Self.dictionaryURL)
    private lazy var mainWindow = MainWindowController(actions: self, dictionaryPane: dictionaryPane)

    // What the window's status column reports; the accessibility grant is read
    // live because the user can revoke it in System Settings at any time.
    private var microphoneGrant: Grant = .pending
    private var modelGrant: Grant = .pending
    private var accessibilityGrant: Grant { AXIsProcessTrusted() ? .granted : .unknown }

    private static let onboardingKey = "hasDismissedOnboarding"
    private static let soundCuesKey = "playsSoundCues"
    private static let stopOnSilenceKey = "stopsOnSilence"

    /// Absent means on: the cues are the default, and only a click turns them off.
    private var soundCues: Bool {
        UserDefaults.standard.object(forKey: Self.soundCuesKey) as? Bool ?? true
    }

    /// Absent means on, as it always was — silence ending the recording is the
    /// default, and only a click hands that job to the shortcut.
    private var stopOnSilence: Bool {
        UserDefaults.standard.object(forKey: Self.stopOnSilenceKey) as? Bool ?? true
    }

    /// The last transcript deleted from the window, for as long as undo can reach it.
    private var lastDeleted: Transcript?

    private var update: UpdateStatus = .idle

    private var shortcutIsBound: Bool { hotKey?.isRegistered == true }

    /// The state to be in when nothing is happening. Going through this rather
    /// than straight to `.idle` is what stops a finished model load, or a
    /// discarded recording, from reporting "Ready" over a shortcut that never
    /// bound. The rule itself lives in VoiceKeyCore, shared with the Windows build.
    private var settled: State {
        switch DictationStatus.settled(shortcutIsBound: shortcutIsBound, shortcut: shortcutLabel) {
        case .error(let message): return .error(message)
        default: return .idle
        }
    }

    private func registerHotKey() {
        let d = UserDefaults.standard
        let code = d.object(forKey: "hotKeyCode") as? UInt32 ?? UInt32(kVK_ANSI_D)
        let mods = d.object(forKey: "hotKeyModifiers") as? UInt32 ?? UInt32(controlKey | optionKey)
        hotKey = nil // unregister the old one before claiming the new combo
        hotKey = HotKey(keyCode: code, modifiers: mods,
                        onPress: { [weak self] in self?.hotKeyPressed() },
                        onRelease: { [weak self] in self?.hotKeyReleased() })
        Log.line("hotkey bound to \(shortcutLabel) (registered=\(shortcutIsBound))")
        if !shortcutIsBound { state = settled }
    }

    @objc private func changeShortcut() {
        capture.begin { [weak self] code, mods, label in
            guard let self else { return }
            // Rebinding can only fix one error — the old shortcut being taken.
            // Any other error (a model that would not load) has to survive this.
            let wasBlockedByTheShortcut = self.isBlockedByShortcut
            let d = UserDefaults.standard
            d.set(code, forKey: "hotKeyCode")
            d.set(mods, forKey: "hotKeyModifiers")
            d.set(label, forKey: "hotKeyLabel")
            self.registerHotKey()
            if wasBlockedByTheShortcut, self.shortcutIsBound { self.state = self.settled }
            self.syncUI()
        }
    }

    private var isBlockedByShortcut: Bool {
        guard case .error(let message) = state else { return false }
        return message == "\(shortcutLabel) is taken by another app"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.trimIfLarge()
        Log.line("launched")
        history = TranscriptHistory.load(from: Self.historyURL) ?? TranscriptHistory()
        Log.line("history loaded — \(history.records.count) transcripts")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = buildMenu()
        // The menu is popped by hand rather than handed to the status item, so a
        // double-click can mean "open the window" — see statusItemClicked().
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installMainMenu()
        syncUI()
        mainWindow.show()

        registerHotKey()
        Task { await checkForUpdate(silent: true) }

        recorder.onAutoStop = { [weak self] in
            guard let self, case .recording = self.state else { return }
            Log.line("recorder stopped itself — trailing silence or the length cap")
            self.finishRecording()
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Log.line("microphone access granted=\(granted)")
            DispatchQueue.main.async {
                self.microphoneGrant = granted ? .granted : .denied
                if granted { self.syncUI() } else { self.state = .error("Microphone access denied") }
            }
        }
        // opens System Settings with the app pre-listed if not yet trusted
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        Log.line("accessibility trusted=\(AXIsProcessTrustedWithOptions(opts))")

        Task {
            do {
                try await transcriber.load()
                Log.line("model loaded")
                await MainActor.run {
                    self.modelGrant = .granted
                    self.state = self.settled
                }
            } catch {
                Log.line("model load FAILED: \(error)")
                await MainActor.run {
                    self.modelGrant = .denied
                    self.state = .error("Model load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Double-clicking the app while it is already running reopens the window —
    /// without this an agent app simply flashes and does nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    /// Agent apps never display a menu bar, but key equivalents still route
    /// through it — without one, Cmd+C/V do not work in the window's fields.
    private func installMainMenu() {
        let main = NSMenu()

        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                       ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                       ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector((selector)), keyEquivalent: key)
        }
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find", action: #selector(findInWindow), keyEquivalent: "f")
        find.target = self
        edit.addItem(find)

        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: Selector(("performClose:")), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Quit VoiceKey",
                           action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: - Menu

    /// One click opens the menu, two open the window. A single click therefore
    /// has to wait out the double-click interval before it can commit to the
    /// menu; a right-click skips the wait, since it can only mean the menu.
    @objc private func statusItemClicked() {
        pendingMenuPopUp?.cancel()
        let event = NSApp.currentEvent
        let wantsMenuNow = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if wantsMenuNow {
            popUpMenu()
        } else if (event?.clickCount ?? 1) >= 2 {
            Log.line("status item double-clicked — opening the window")
            mainWindow.show()
        } else {
            let popUp = DispatchWorkItem { [weak self] in self?.popUpMenu() }
            pendingMenuPopUp = popUp
            DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.3),
                                          execute: popUp)
        }
    }

    /// Handing the menu over for the length of one click is what keeps the status
    /// item highlighted while it is open; `performClick` returns once it closes.
    private func popUpMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // give the button's action back for the next click
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false // "Copy Last Transcript" enables on content, not on target

        headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Only shown in the error state, where it is the actionable item.
        privacyItem = item("Open Privacy Settings…", #selector(openPrivacySettings))
        privacyItem.isHidden = true
        menu.addItem(privacyItem)

        toggleItem = item("Start Dictation", #selector(hotKeyPressed))
        menu.addItem(toggleItem)
        copyLastItem = item("Copy Last Transcript", #selector(copyLastTranscript), key: "v",
                            modifiers: [.command, .shift])
        menu.addItem(copyLastItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Transcripts"))

        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        historyMenu = NSMenu(title: "Recent")
        historyMenu.autoenablesItems = false
        recent.submenu = historyMenu
        menu.addItem(recent)
        rebuildHistoryMenu()

        menu.addItem(item("All Transcripts…", #selector(openTranscripts)))
        menu.addItem(item("Dictionary…", #selector(editDictionary)))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Setup"))
        menu.addItem(item("Shortcut…", #selector(changeShortcut)))
        menu.addItem(item("Diagnostics Log", #selector(openLog)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceKey",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        if let modifiers { menuItem.keyEquivalentModifierMask = modifiers }
        return menuItem
    }

    /// State on the left in the menu font, the meta value right-aligned in a
    /// dim 11pt — one item, two columns, no custom view.
    private static func headerTitle(_ presentation: StatusPresentation) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 210)]
        let menuFont = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(
            string: presentation.title,
            attributes: [.font: NSFont.systemFont(ofSize: menuFont.pointSize, weight: .semibold),
                         .paragraphStyle: paragraph])
        guard !presentation.meta.isEmpty else { return title }
        title.append(NSAttributedString(
            string: "\t" + presentation.meta,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: paragraph]))
        return title
    }

    private var currentStatus: DictationStatus {
        switch state {
        case .loading: return .loading
        case .idle: return .idle
        case .recording:
            let started = recordingStartedAt ?? Date()
            return .recording(elapsed: Int(Date().timeIntervalSince(started)))
        case .transcribing: return .transcribing
        case .error(let message): return .error(message)
        }
    }

    private func syncUI() {
        let status = currentStatus
        let presentation = StatusPresentation.make(for: status, shortcut: shortcutLabel,
                                                   modelName: Transcriber.modelName)
        statusItem.button?.image = MenuBarGlyph.image(presentation.glyph == .recording ? .recording : .idle)
        statusItem.button?.appearsDisabled = presentation.isDimmed
        statusItem.button?.toolTip = "VoiceKey — \(presentation.title)"
        headerItem.attributedTitle = Self.headerTitle(presentation)
        toggleItem.title = presentation.action
        copyLastItem.isEnabled = !history.entries.isEmpty
        if case .error = state { privacyItem.isHidden = false } else { privacyItem.isHidden = true }

        mainWindow.apply(MainWindowModel(
            history: history, status: status, shortcut: shortcutLabel,
            microphone: microphoneGrant, accessibility: accessibilityGrant, model: modelGrant,
            showsOnboarding: WindowPresentation.showsOnboarding(
                dismissed: UserDefaults.standard.bool(forKey: Self.onboardingKey),
                transcripts: history.records.count),
            launchAtLogin: LoginItem.state, soundCues: soundCues,
            stopOnSilence: stopOnSilence, update: update))
    }

    /// The header's elapsed time ticks once a second while recording; the menu
    /// picks the new title up whether or not it happens to be open.
    private func syncTimer() {
        if case .recording = state {
            guard tickTimer == nil else { return }
            recordingStartedAt = Date()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.syncUI()
            }
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
            recordingStartedAt = nil
        }
    }

    // MARK: - Dictation

    @objc private func hotKeyPressed() {
        Log.line("hotkey press (state=\(state))")
        switch state {
        case .idle:
            do {
                try recorder.start(stopOnSilence: stopOnSilence)
                if soundCues { SoundCue.recordingStarted() }
                recordingStartedByPressAt = Date()
                state = .recording
            } catch {
                Log.line("recorder.start FAILED: \(error)")
                state = .error("Mic not ready — grant microphone access")
            }
        case .recording:
            recordingStartedByPressAt = nil // this press is a toggle-stop; ignore its release
            finishRecording()
        case .error:
            // "Retry" from the menu: rebind the shortcut if that is what failed,
            // then report wherever that leaves us.
            if !shortcutIsBound { registerHotKey() } else { state = settled }
        case .loading, .transcribing:
            break
        }
    }

    private func hotKeyReleased() {
        guard case .recording = state, let started = recordingStartedByPressAt else { return }
        let held = Date().timeIntervalSince(started)
        Log.line("hotkey release after \(String(format: "%.2f", held))s")
        guard held >= holdThreshold else { return } // quick tap → stay in toggle mode
        finishRecording()
    }

    // MARK: - Updates

    /// - Parameter silent: The check at launch. Nobody asked for it, so it
    ///   reports only good news — a failure there is the network's business,
    ///   not the user's.
    @MainActor
    private func checkForUpdate(silent: Bool = false) async {
        if !silent { setUpdate(.checking) }
        let result = await Updater.check()
        if silent, case .failed = result {
            setUpdate(.idle)
            return
        }
        setUpdate(result)
    }

    /// Downloads and stages the new build, then quits — the script the updater
    /// left behind copies it in once this process is gone, and opens it again.
    @MainActor
    private func installUpdate() async {
        guard case .available(_, let url) = update else { return }
        setUpdate(.downloading(percent: 0))
        let result = await Updater.install(from: url) { percent in
            Task { @MainActor in self.setUpdate(.downloading(percent: percent)) }
        }
        setUpdate(result)
        if case .installing = result { NSApp.terminate(nil) }
    }

    private func setUpdate(_ status: UpdateStatus) {
        update = status
        syncUI()
    }

    private func finishRecording() {
        recordingStartedByPressAt = nil
        state = .transcribing
        let (samples, heardSpeech) = recorder.stop()
        // After stop(), so the cue is never in the recording it announces.
        if soundCues { SoundCue.recordingStopped() }
        let duration = Double(samples.count) / 16_000 // the recorder resamples to 16kHz mono
        Log.line("stopped — \(samples.count) samples (\(samples.count / 16_000)s), heardSpeech=\(heardSpeech)")
        guard heardSpeech else {
            state = settled
            return
        }
        // Reload each time so edits to dictionary.json apply without a restart.
        // Missing/broken file → empty dictionary, NOT the template: template
        // rules must never rewrite words the user didn't opt into.
        let dictionary = VocabularyDictionary.load(from: Self.dictionaryURL) ?? VocabularyDictionary()
        Task {
            do {
                let raw = try await transcriber.transcribe(samples, vocabularyPrompt: dictionary.promptText)
                Log.line("transcript: \"\(raw)\"")
                await MainActor.run {
                    let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    let text = Self.polish(raw, dictionary: dictionary, bundleID: bundleID)
                    Log.line("polished for \(bundleID ?? "unknown app"): \"\(text)\"")
                    guard !text.isEmpty else {
                        self.state = self.settled
                        return
                    }
                    let pasted = self.deliver(text, into: bundleID)
                    self.record(text, duration: duration)
                    self.state = pasted
                        ? self.settled
                        : .error("Copied — grant Accessibility to auto-paste")
                }
            } catch {
                Log.line("transcription FAILED: \(error)")
                await MainActor.run { self.state = .error("Transcription failed: \(error.localizedDescription)") }
            }
        }
    }

    /// Raw whisper output → pasteable text: drop non-speech annotations, strip
    /// fillers/stutters, apply the user's replacement rules, then format for
    /// the app the text lands in. Pure — all logic lives in VoiceKeyCore.
    private static func polish(_ raw: String, dictionary: VocabularyDictionary, bundleID: String?) -> String {
        guard !TranscriptCleaner.isNonSpeechAnnotation(raw) else { return "" }
        let cleaned = TranscriptCleaner.clean(raw)
        let replaced = dictionary.applyingReplacements(to: cleaned)
        return DictationMode.mode(forBundleID: bundleID).format(replaced)
    }

    /// Returns false when the text only reached the clipboard *and* the user has
    /// something to fix — a missing Accessibility grant.
    ///
    /// `bundleID` is the app the text is headed for; nil means "whatever has
    /// focus by the time this runs", which is what the window's own Insert wants
    /// after it has stepped aside.
    private func deliver(_ text: String, into bundleID: String? = nil) -> Bool {
        guard DictationMode.insertsAtCursor(frontmostBundleID: bundleID,
                                            ownBundleID: Bundle.main.bundleIdentifier) else {
            // Pasting here would land in our own search field and filter the
            // library to this one transcript. It is in the list either way.
            Log.line("VoiceKey is frontmost — copied instead of pasting into our own window")
            copy(text)
            return true
        }
        guard AXIsProcessTrusted() else {
            // degrade gracefully: clipboard + hint instead of a silent no-op
            Log.line("accessibility NOT trusted — clipboard fallback")
            copy(text)
            return false
        }
        Log.line("pasting at cursor")
        TextInserter.insert(text)
        return true
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Menu actions

    @objc private func copyLastTranscript() {
        guard let latest = history.entries.first else { return }
        copy(latest)
    }

    @objc private func openTranscripts() {
        mainWindow.show(.transcripts)
    }

    @objc private func editDictionary() {
        mainWindow.show(.dictionary)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func findInWindow() {
        mainWindow.show(.transcripts)
        mainWindow.focusSearch()
    }

    /// Whichever grant is actually missing decides the pane — checked at click
    /// time, so no error-flavour has to be threaded through the state machine.
    @objc private func openPrivacySettings() {
        let pane = AXIsProcessTrusted() ? "Privacy_Microphone" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func rebuildHistoryMenu() {
        historyMenu.removeAllItems()
        guard !history.entries.isEmpty else {
            let empty = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
            return
        }
        for entry in history.entries {
            let historyItem = item(TranscriptHistory.menuTitle(for: entry), #selector(copyHistoryEntry(_:)))
            historyItem.representedObject = entry
            historyItem.toolTip = entry
            historyMenu.addItem(historyItem)
        }
        historyMenu.addItem(.separator())
        historyMenu.addItem(item("Clear History", #selector(clearHistory)))
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        copy(text)
    }

    @objc private func clearHistory() {
        history = history.cleared()
        persistHistory()
        rebuildHistoryMenu()
        syncUI()
    }

    // MARK: - History

    /// Records a finished dictation. The getting-started strip retires itself on
    /// the count, so nothing has to be flagged here.
    private func record(_ text: String, duration: TimeInterval) {
        history = history.adding(text, at: Date(), duration: duration)
        persistHistory()
        rebuildHistoryMenu()
    }

    private func persistHistory() {
        do {
            try FileManager.default.createDirectory(
                at: Self.historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try history.save(to: Self.historyURL)
        } catch {
            Log.line("history save FAILED: \(error)")
        }
    }
}

// MARK: - What the window asks for

extension AppController: MainWindowActions {

    func windowCopy(_ text: String) {
        copy(text)
    }

    func windowAddTerm(from text: String) {
        dictionaryPane.addTerm(suggestion: VocabularyDictionary.suggestedTerm(from: text))
    }

    func windowDelete(_ id: Transcript.ID) {
        lastDeleted = history.records.first { $0.id == id }
        history = history.removing(id)
        persistHistory()
        rebuildHistoryMenu()
        syncUI()
    }

    func windowUndoDelete() {
        guard let record = lastDeleted else { return }
        lastDeleted = nil
        history = history.restoring(record)
        persistHistory()
        rebuildHistoryMenu()
        syncUI()
    }

    func windowDeleteAll() {
        clearHistory()
    }

    /// The whole log as one plain-text file, wherever the user points. Export is
    /// a copy — nothing is removed and nothing leaves the machine on its own.
    func windowExportAll() {
        let panel = NSSavePanel()
        panel.title = "Export transcripts"
        panel.nameFieldStringValue = "VoiceKey transcripts.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try history.exportText().write(to: url, atomically: true, encoding: .utf8)
            Log.line("exported \(history.records.count) transcripts")
        } catch {
            Log.line("export FAILED: \(error)")
            let alert = NSAlert()
            alert.messageText = "Could not write the file"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func windowDismissOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        syncUI()
    }

    func windowClickUpdate() {
        switch AppUpdate.click(update) {
        case .check: Task { await checkForUpdate() }
        case .install: Task { await installUpdate() }
        case .none: break
        }
    }

    func windowToggleSoundCues() {
        UserDefaults.standard.set(!soundCues, forKey: Self.soundCuesKey)
        syncUI()
    }

    /// Takes effect on the next recording — the one in flight keeps the rule it
    /// started under, so a click cannot cut a sentence short.
    func windowToggleStopOnSilence() {
        UserDefaults.standard.set(!stopOnSilence, forKey: Self.stopOnSilenceKey)
        syncUI()
    }

    func windowChangeShortcut() {
        changeShortcut()
    }

    /// Acts on what the system reports right now, not on what the row was last
    /// drawn with — the switch can also be flipped in System Settings.
    func windowToggleLaunchAtLogin() {
        switch LaunchAtLogin.click(LoginItem.state) {
        case .enable: LoginItem.set(true)
        case .disable: LoginItem.set(false)
        case .openSettings: LoginItem.openSettings()
        }
        syncUI()
    }

    func windowOpenLog() {
        openLog()
    }

    func windowOpenPrivacy(for subject: WindowPresentation.Subject) {
        let pane: String
        switch subject {
        case .microphone: pane = "Privacy_Microphone"
        case .accessibility: pane = "Privacy_Accessibility"
        case .model: return // nothing to grant — the model downloads itself
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }

}
