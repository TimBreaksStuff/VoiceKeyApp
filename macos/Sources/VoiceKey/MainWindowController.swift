import AppKit
import QuartzCore
import VoiceKeyCore

/// Everything the window draws. AppController owns it and pushes a new value
/// whenever something changes; the window diffs it and redraws what moved.
struct MainWindowModel: Equatable {
    var history = TranscriptHistory()
    var status: DictationStatus = .loading
    var shortcut = "⌃⌥D"
    var microphone: Grant = .pending
    var accessibility: Grant = .pending
    var model: Grant = .pending
    /// The getting-started strip, until it retires itself.
    var showsOnboarding = true
    /// What the system reports about opening VoiceKey at login.
    var launchAtLogin: LaunchAtLoginState = .off
    /// Whether starting and stopping a dictation plays its cue.
    var soundCues = true
    /// How far the check for a newer VoiceKey has got.
    var update: UpdateStatus = .idle
}

/// What the window asks the app to do. Keeps AppKit glue out of AppController's
/// state machine and the state machine out of the views.
protocol MainWindowActions: AnyObject {
    func windowCopy(_ text: String)
    func windowAddTerm(from text: String)
    func windowDelete(_ id: Transcript.ID)
    /// Puts the last deleted transcript back — what the undo toast calls.
    func windowUndoDelete()
    func windowDeleteAll()
    func windowExportAll()
    func windowDismissOnboarding()
    func windowChangeShortcut()
    func windowToggleLaunchAtLogin()
    func windowToggleSoundCues()
    /// Check, install, or nothing — whichever the row's state calls for.
    func windowClickUpdate()
    func windowOpenLog()
    func windowOpenPrivacy(for subject: WindowPresentation.Subject)
}

/// The app's one window: a fixed 236pt sidebar and a 76pt header over one
/// scrolling pane. Layout numbers come straight from the design handoff.
final class MainWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    enum Pane: Equatable { case transcripts, dictionary }

    /// The design's window starts at its own top edge; a full-size content view
    /// on macOS starts under the traffic lights. Every band that the handoff
    /// hangs off the top — the sidebar's brand row, the header — clears the
    /// titlebar by this much first, so the two keep the spacing they had.
    private static let titlebar: CGFloat = 25

    private weak var actions: MainWindowActions?
    private let dictionaryPane: DictionaryPane
    private var model = MainWindowModel()
    private var pane: Pane = .transcripts

    private var window: NSWindow?
    private let paneTitle = Theme.label("Transcripts", font: Theme.serif(27, weight: .medium),
                                        tracking: -0.01)
    private let dateLabel = Theme.sectionLabel("", size: 11)
    private let searchField = NSTextField()
    private let searchShell = NSView()
    private let statusPill = StatusPillView()
    private let weekWords = Theme.label("", font: Theme.serif(19))
    private let weekPace = Theme.label("", font: Theme.serif(19))
    private let weekSaved = Theme.label("", font: Theme.serif(19))
    private let paneContainer = NSView()
    private var navRows: [Pane: SidebarNavRow] = [:]
    private var launchAtLoginLink: SidebarLink?
    private var soundCuesLink: SidebarLink?
    private var settingsLink: SidebarLink?
    private var updateNotice: SidebarLink?
    private var updateRow: SidebarLink?
    private let settingsPopover = NSPopover()
    private let permissionsPopover = NSPopover()
    private let helpPopover = NSPopover()
    private let permissionsList = NSStackView()
    private let helpHoldStep = WrappingLabel(attributed: NSAttributedString(string: ""))

    private lazy var transcriptsPane = TranscriptsPane(
        onAction: { [weak self] action in self?.perform(action) })

    init(actions: MainWindowActions, dictionaryPane: DictionaryPane) {
        self.actions = actions
        self.dictionaryPane = dictionaryPane
        super.init()
        dictionaryPane.onSaved = { [weak self, weak dictionaryPane] in
            guard let self, let dictionaryPane else { return }
            self.navRows[.dictionary]?.count = TranscriptStats.grouped(dictionaryPane.entryCount)
        }
    }

    // MARK: - Showing

    func show(_ pane: Pane = .transcripts) {
        let window = self.window ?? makeWindow()
        self.window = window
        select(pane)
        render(model, rebuildList: true) // first sight of the window, or a pane just swapped in
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Redraws whatever the new model changed. The transcript list is rebuilt
    /// only when it actually differs — the recording clock updates the status
    /// every second and must not throw the list away underneath the user.
    func apply(_ model: MainWindowModel) {
        let previous = self.model
        self.model = model
        guard window != nil else { return }
        render(model, rebuildList: previous.history != model.history
                   || previous.shortcut != model.shortcut)
    }

    private func render(_ model: MainWindowModel, rebuildList: Bool) {
        let presentation = WindowPresentation.make(
            status: model.status, microphone: model.microphone,
            accessibility: model.accessibility, model: model.model)

        dateLabel.attributedStringValue = Theme.attributed(
            presentation.dateLine.uppercased(), font: Theme.mono(11),
            color: Theme.muted3, tracking: 0.1)
        statusPill.apply(presentation.pill)
        rebuildPermissions(presentation.permissions)
        applyLaunchAtLogin(model.launchAtLogin)
        soundCuesLink?.title = CueSound.label(model.soundCues)
        updateRow?.title = AppUpdate.label(model.update)
        updateNotice?.title = AppUpdate.label(model.update)
        updateNotice?.isHidden = !AppUpdate.isVisible(model.update)
        applyStats(TranscriptStats.make(from: model.history.records))

        navRows[.transcripts]?.count = TranscriptStats.grouped(model.history.records.count)
        navRows[.dictionary]?.count = TranscriptStats.grouped(dictionaryPane.entryCount)

        transcriptsPane.apply(model, rebuildList: rebuildList)
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let size = Self.startingSize()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                          .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "VoiceKey"
        window.minSize = NSSize(width: 1000, height: 640)
        window.isReleasedWhenClosed = false // reopened from the menu, so it outlives its close
        window.backgroundColor = Theme.paper
        window.appearance = NSAppearance(named: .aqua) // the palette is a light one; see the spec
        window.delegate = self
        window.center()
        window.contentView = makeContent()
        return window
    }

    /// 1440×900 where it fits, and as much of it as the screen allows otherwise.
    private static func startingSize() -> NSSize {
        guard let visible = NSScreen.main?.visibleFrame else { return NSSize(width: 1440, height: 900) }
        return NSSize(width: min(1440, visible.width - 80), height: min(900, visible.height - 80))
    }

    private func makeContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.paper.cgColor

        let sidebar = makeSidebar()
        let divider = Theme.rule(Theme.border, vertical: true)
        let column = makeContentColumn()
        [sidebar, divider, column].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 236),

            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            column.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    // MARK: - Sidebar

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = Theme.chrome.cgColor

        let brand = makeBrandRow()

        let libraryLabel = Theme.sectionLabel("Library")
        let libraryLabelRow = inset(libraryLabel, left: 8)

        let transcripts = navRow(.transcripts, title: "Transcripts")
        let dictionary = navRow(.dictionary, title: "Dictionary")
        let nav = NSStackView(views: [libraryLabelRow, transcripts, dictionary])
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 2
        nav.setCustomSpacing(8, after: libraryLabelRow)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .vertical)

        let week = makeWeekCard()
        let footer = makeFooter()

        let stack = NSStackView(views: [brand, nav, spacer, week, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(26, after: brand)
        stack.setCustomSpacing(26, after: spacer)
        stack.setCustomSpacing(16, after: week)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            // the handoff's 22pt brand inset, below the titlebar
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor,
                                       constant: Self.titlebar + 22),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            nav.widthAnchor.constraint(equalTo: stack.widthAnchor),
            week.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            transcripts.widthAnchor.constraint(equalTo: nav.widthAnchor),
            dictionary.widthAnchor.constraint(equalTo: nav.widthAnchor),
        ])
        return sidebar
    }

    /// Wraps a view so it can carry its own left inset inside a leading-aligned stack.
    private func inset(_ view: NSView, left: CGFloat) -> NSView {
        let holder = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: holder.topAnchor),
            view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: left),
            view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        ])
        return holder
    }

    private func makeBrandRow() -> NSView {
        let name = Theme.label("VoiceKey", font: Theme.serif(23, weight: .semibold), tracking: -0.01)
        let chip = LocalChip()
        let row = NSStackView(views: [name, chip])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        return row
    }

    private func navRow(_ pane: Pane, title: String) -> SidebarNavRow {
        let row = SidebarNavRow(title: title) { [weak self] in self?.select(pane) }
        navRows[pane] = row
        return row
    }

    /// Honest labels: what was dictated this week, not a vanity streak.
    private func makeWeekCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.paper.cgColor
        card.layer?.borderColor = Theme.border.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 10

        let rows = NSStackView(views: [
            Theme.sectionLabel("This week"),
            weekRow("Words dictated", value: weekWords),
            weekRow("Average pace", value: weekPace),
            weekRow("Typing saved", value: weekSaved),
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rows)

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    private func weekRow(_ title: String, value: NSTextField) -> NSView {
        let row = NSView()
        let label = Theme.label(title, font: Theme.sans(14), color: Theme.ink3)
        [label, value].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.firstBaselineAnchor.constraint(equalTo: value.firstBaselineAnchor),
            value.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            value.topAnchor.constraint(equalTo: row.topAnchor),
            value.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            value.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 10),
        ])
        return row
    }

    private func makeFooter() -> NSView {
        let settings = SidebarLink(title: "Settings", icon: Theme.gear(size: 14)) { [weak self] in
            self?.showSettings()
        }
        settingsLink = settings

        // Only here when there is news: see AppUpdate.isVisible.
        let notice = SidebarLink(title: "", color: Theme.clay, hover: Theme.clayHover) { [weak self] in
            self?.actions?.windowClickUpdate()
        }
        notice.isHidden = true
        updateNotice = notice

        let rule = Theme.rule(Theme.border)
        let stack = NSStackView(views: [rule, settings, notice])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: rule)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    // MARK: - Settings

    /// Settings opens beside its row, the way Help does — the window stays where
    /// it is, so a shortcut can be tried straight after changing it.
    private func showSettings() {
        guard let anchor = settingsLink else { return }
        guard !settingsPopover.isShown else {
            settingsPopover.performClose(nil)
            return
        }
        settingsPopover.behavior = .transient
        settingsPopover.contentViewController = wrap(padded(makeSettingsCard(), by: 18))
        settingsPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    private func makeSettingsCard() -> NSView {
        let heading = Theme.label("Settings", font: Theme.serif(17))

        let launch = SidebarLink(title: LaunchAtLogin.label("Open at login", model.launchAtLogin)) { [weak self] in
            self?.actions?.windowToggleLaunchAtLogin()
        }
        launchAtLoginLink = launch

        let sounds = SidebarLink(title: CueSound.label(model.soundCues)) { [weak self] in
            self?.actions?.windowToggleSoundCues()
        }
        soundCuesLink = sounds

        let shortcut = SidebarLink(title: "Shortcut") { [weak self] in
            self?.settingsPopover.performClose(nil)
            self?.actions?.windowChangeShortcut()
        }
        let rule = Theme.rule(Theme.borderRow)
        let log = SidebarLink(title: "Diagnostics log") { [weak self] in
            self?.settingsPopover.performClose(nil)
            self?.actions?.windowOpenLog()
        }
        // Help hangs off the Settings row, since that is where its link now lives.
        let help = SidebarLink(title: "Help & shortcuts") { [weak self] in
            guard let self, let link = self.settingsLink else { return }
            self.settingsPopover.performClose(nil)
            self.showHelp(from: link, edge: .maxX)
        }
        let update = SidebarLink(title: AppUpdate.label(model.update)) { [weak self] in
            self?.actions?.windowClickUpdate()
        }
        updateRow = update

        let version = Theme.label("VoiceKey \(Updater.currentVersion)",
                                  font: Theme.sans(13), color: Theme.ink3)

        let stack = NSStackView(views: [heading, launch, sounds, shortcut, rule,
                                        log, help, update, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(14, after: shortcut)
        stack.setCustomSpacing(12, after: rule)
        stack.setCustomSpacing(12, after: update)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 224).isActive = true
        return stack
    }

    /// The footer row carries the state the system reports, not a preference of
    /// our own — so a switch flipped in System Settings shows up here on the
    /// next redraw rather than at the next launch.
    private func applyLaunchAtLogin(_ state: LaunchAtLoginState) {
        launchAtLoginLink?.title = LaunchAtLogin.label("Open at login", state)
        launchAtLoginLink?.toolTip = state == .blocked
            ? "Switched off in System Settings › General › Login Items. Click to open it."
            : nil
    }

    private func select(_ pane: Pane) {
        self.pane = pane
        navRows.forEach { $0.value.isSelected = $0.key == pane }
        paneTitle.attributedStringValue = Theme.attributed(
            pane == .transcripts ? "Transcripts" : "Dictionary",
            font: Theme.serif(27, weight: .medium), tracking: -0.01)
        searchShell.isHidden = pane != .transcripts

        let view = pane == .transcripts ? transcriptsPane.view : dictionaryPane.view
        guard paneContainer.subviews.first !== view else { return }
        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ])
        if pane == .dictionary { dictionaryPane.reload() }
    }

    // MARK: - Header

    private func makeContentColumn() -> NSView {
        let column = NSView()

        let title = NSStackView(views: [paneTitle, dateLabel])
        title.orientation = .vertical
        title.alignment = .leading
        title.spacing = 3

        let controls = NSStackView(views: [makeSearchField(), statusPill])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12

        statusPill.onClick = { [weak self] in self?.togglePermissions() }

        let header = NSView()
        [title, controls].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 76),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),

            controls.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor,
                                              constant: 24),
        ])

        let divider = Theme.rule(Theme.borderSoft)
        [header, divider, paneContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: column.topAnchor,
                                        constant: Self.titlebar),
            header.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            paneContainer.topAnchor.constraint(equalTo: divider.bottomAnchor),
            paneContainer.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: column.bottomAnchor),
        ])
        return column
    }

    private func makeSearchField() -> NSView {
        searchShell.wantsLayer = true
        searchShell.layer?.backgroundColor = Theme.field.cgColor
        searchShell.layer?.borderColor = Theme.border.cgColor
        searchShell.layer?.borderWidth = 1
        searchShell.layer?.cornerRadius = 9

        let glyph = Theme.label("⌕", font: Theme.mono(13), color: Theme.muted3)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = Theme.sans(14)
        searchField.textColor = Theme.ink()
        searchField.placeholderString = "Search transcripts"
        searchField.delegate = self
        searchField.cell?.wraps = false
        searchField.cell?.isScrollable = true

        [glyph, searchField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            searchShell.addSubview($0)
        }
        NSLayoutConstraint.activate([
            searchShell.widthAnchor.constraint(equalToConstant: 280),
            searchShell.heightAnchor.constraint(equalToConstant: 38),
            glyph.leadingAnchor.constraint(equalTo: searchShell.leadingAnchor, constant: 12),
            glyph.centerYAnchor.constraint(equalTo: searchShell.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 9),
            searchField.trailingAnchor.constraint(equalTo: searchShell.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchShell.centerYAnchor),
        ])
        return searchShell
    }

    func controlTextDidChange(_ notification: Notification) {
        transcriptsPane.setQuery(searchField.stringValue)
    }

    /// Esc in the search field clears it rather than closing the window.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        return clearSearch()
    }

    /// ⌘F reaches the search box from anywhere in the window; Esc clears it.
    func focusSearch() {
        select(.transcripts)
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    @discardableResult
    func clearSearch() -> Bool {
        guard !searchField.stringValue.isEmpty else { return false }
        searchField.stringValue = ""
        transcriptsPane.setQuery("")
        return true
    }

    // MARK: - The permissions popover

    private func togglePermissions() {
        guard !permissionsPopover.isShown else {
            permissionsPopover.performClose(nil)
            return
        }
        permissionsPopover.behavior = .transient
        permissionsPopover.contentViewController = wrap(padded(permissionsList, by: 14))
        permissionsPopover.show(relativeTo: statusPill.bounds, of: statusPill, preferredEdge: .maxY)
    }

    private func rebuildPermissions(_ lines: [WindowPresentation.PermissionLine]) {
        permissionsList.orientation = .vertical
        permissionsList.alignment = .leading
        permissionsList.spacing = 6
        permissionsList.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for line in lines {
            let label = Theme.label(line.text, font: Theme.mono(12),
                                    color: line.needsAttention ? Theme.clay : Theme.muted3)
            guard line.needsAttention else {
                permissionsList.addArrangedSubview(label)
                continue
            }
            let subject = line.subject
            let row = ClickableRow(content: label,
                                   insets: NSEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)) {
                [weak self] in
                self?.permissionsPopover.performClose(nil)
                self?.actions?.windowOpenPrivacy(for: subject)
            }
            permissionsList.addArrangedSubview(row)
        }
    }

    // MARK: - Help

    /// The walkthrough, beside whatever asked for it: to the right of the sidebar
    /// link, under a button in the pane.
    func showHelp(from anchor: NSView, edge: NSRectEdge) {
        helpHoldStep.attributedStringValue = Theme.attributed(
            "2. Hold \(model.shortcut) and speak. Release when you are done; a quick tap "
                + "instead keeps recording until you tap again.",
            font: Theme.sans(14), color: Theme.ink2, lineHeight: 1.35)

        guard !helpPopover.isShown else {
            helpPopover.performClose(nil)
            return
        }
        helpPopover.behavior = .transient
        helpPopover.contentViewController = wrap(padded(makeHelpCard(), by: 18))
        helpPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    private func makeHelpCard() -> NSView {
        let heading = Theme.label("Dictating with VoiceKey", font: Theme.serif(17))
        let first = WrappingLabel(attributed: Theme.attributed(
            "1. Put the cursor where the text should go — any app, any field.",
            font: Theme.sans(14), color: Theme.ink2, lineHeight: 1.35))
        let third = WrappingLabel(attributed: Theme.attributed(
            "3. VoiceKey transcribes on this Mac and types the text at the cursor.",
            font: Theme.sans(14), color: Theme.ink2, lineHeight: 1.35))
        let rule = Theme.rule(Theme.borderRow)
        let footnote = WrappingLabel(attributed: Theme.attributed(
            "Words it keeps mishearing belong in the Dictionary. The shortcut itself "
                + "can be changed below.",
            font: Theme.sans(13), color: Theme.ink3, lineHeight: 1.35))
        let button = SquareButton(title: "Change shortcut", filled: false) { [weak self] _ in
            self?.helpPopover.performClose(nil)
            self?.actions?.windowChangeShortcut()
        }

        let stack = NSStackView(views: [heading, first, helpHoldStep, third, rule, footnote, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(14, after: third)
        stack.setCustomSpacing(12, after: rule)
        stack.setCustomSpacing(14, after: footnote)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 340),
            rule.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return stack
    }

    /// A popover needs a view controller, and its content needs its own padding.
    private func wrap(_ view: NSView) -> NSViewController {
        let controller = NSViewController()
        controller.view = view
        return controller
    }

    private func padded(_ content: NSView, by inset: CGFloat) -> NSView {
        let holder = NSView()
        holder.wantsLayer = true
        holder.layer?.backgroundColor = Theme.paper.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: holder.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -inset),
            content.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -inset),
        ])
        return holder
    }

    // MARK: - This week

    private func applyStats(_ stats: TranscriptStats) {
        weekWords.attributedStringValue = Theme.attributed(
            stats.words, font: Theme.tabular(Theme.serif(19)))
        weekPace.attributedStringValue = Theme.attributed(
            stats.pace, font: Theme.tabular(Theme.serif(19)))
        weekSaved.attributedStringValue = Theme.attributed(
            stats.typingSaved, font: Theme.tabular(Theme.serif(19)))
    }

    // MARK: - Row actions

    private func perform(_ action: TranscriptsPane.Action) {
        switch action {
        case .copy(let text): actions?.windowCopy(text)
        case .addTerm(let text):
            actions?.windowAddTerm(from: text)
            select(.dictionary)
        case .delete(let id): actions?.windowDelete(id)
        case .undoDelete: actions?.windowUndoDelete()
        case .deleteAll: confirmDeleteAll()
        case .exportAll: actions?.windowExportAll()
        case .dismissOnboarding: actions?.windowDismissOnboarding()
        case .changeShortcut: actions?.windowChangeShortcut()
        case .showHelp(let anchor): showHelp(from: anchor, edge: .maxY)
        }
    }

    /// Deleting every transcript cannot be undone — the history file is rewritten —
    /// so this is the one action that asks first.
    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete every transcript?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        Log.line("delete-all requested — asking for confirmation")
        let answer = alert.runModal()
        Log.line("delete-all answer=\(answer.rawValue)")
        guard answer == .alertFirstButtonReturn else { return }
        actions?.windowDeleteAll()
    }

    func windowWillClose(_ notification: Notification) {
        guard pane == .dictionary else { return }
        dictionaryPane.commitEditing() // a field mid-edit would lose its last change
    }
}

// MARK: - Sidebar pieces

/// A sidebar navigation row: label, count, hover fill, and a paper-on-border
/// treatment when it is the pane on screen.
final class SidebarNavRow: NSView {
    private let action: () -> Void
    private let title: String
    private let titleLabel: NSTextField
    private let countLabel: NSTextField
    private var hovering = false

    var isSelected = false { didSet { restyle() } }
    var count: String = "" {
        didSet {
            countLabel.attributedStringValue = Theme.attributed(
                count, font: Theme.tabular(Theme.mono(12)),
                color: isSelected ? Theme.muted2 : Theme.muted3, alignment: .right)
        }
    }

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        self.title = title
        self.titleLabel = Theme.label(title, font: Theme.sans(15), color: Theme.ink3)
        self.countLabel = Theme.label("", font: Theme.mono(12), color: Theme.muted3,
                                      alignment: .right)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.clear.cgColor

        [titleLabel, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                                                constant: 10),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; restyle() }
    override func mouseUp(with event: NSEvent) { action() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func restyle() {
        layer?.backgroundColor = isSelected
            ? Theme.paper.cgColor
            : (hovering ? Theme.field.cgColor : nil)
        layer?.borderColor = isSelected ? Theme.border.cgColor : NSColor.clear.cgColor
        titleLabel.attributedStringValue = Theme.attributed(
            title, font: Theme.sans(15, weight: isSelected ? .semibold : .regular),
            color: isSelected ? Theme.ink() : Theme.ink3)
        countLabel.attributedStringValue = Theme.attributed(
            count, font: Theme.tabular(Theme.mono(12)),
            color: isSelected ? Theme.muted2 : Theme.muted3, alignment: .right)
    }
}

/// A plain text link in the sidebar footer: darkens under the pointer.
final class SidebarLink: NSView {
    private let action: () -> Void
    private let colour: NSColor
    private let hoverColour: NSColor
    private let label: NSTextField

    /// Settable: the launch-at-login row carries its state in its title.
    var title: String { didSet { recolour(colour) } }

    /// The gear beside "Settings"; nil for every other row.
    private let icon: NSImageView?

    init(title: String, color: NSColor = Theme.ink3, hover: NSColor = Theme.ink(),
         icon: NSImage? = nil, action: @escaping () -> Void) {
        self.action = action
        self.title = title
        self.colour = color
        self.hoverColour = hover
        self.label = Theme.label(title, font: Theme.sans(14), color: color)
        self.icon = icon.map { image in
            let view = NSImageView(image: image)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        guard let icon = self.icon else {
            label.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            return
        }
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { recolour(hoverColour) }
    override func mouseExited(with event: NSEvent) { recolour(colour) }
    override func mouseUp(with event: NSEvent) { action() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func recolour(_ colour: NSColor) {
        label.attributedStringValue = Theme.attributed(title, font: Theme.sans(14), color: colour)
        icon?.contentTintColor = colour
    }
}

/// A row that highlights under the pointer and runs a closure when clicked.
final class ClickableRow: NSView {
    private let action: () -> Void
    private var hovering = false

    init(content: NSView, insets: NSEdgeInsets, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                              constant: -insets.right),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateBackground() }
    override func mouseUp(with event: NSEvent) { action() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func updateBackground() {
        layer?.backgroundColor = hovering ? Theme.field.cgColor : nil
    }
}

/// The green "LOCAL" chip next to the brand.
final class LocalChip: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = Theme.greenBorder.cgColor
        layer?.backgroundColor = Theme.greenBg.cgColor

        let label = Theme.label("LOCAL", font: Theme.mono(10), color: Theme.green, tracking: 0.08)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// The engine pill: a dot, the state, and "· on-device". Coloured by tone, and
/// clickable — the granular permission state is one click behind it.
final class StatusPillView: NSView {
    var onClick: (() -> Void)?

    private let dot = NSView()
    private let label = Theme.label("", font: Theme.sans(14, weight: .medium))

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        let suffix = Theme.label("· on-device", font: Theme.mono(11), color: Theme.greenMeta)

        [dot, label, suffix].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            suffix.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            suffix.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            suffix.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ pill: WindowPresentation.Pill) {
        let palette = Self.palette(for: pill.tone)
        layer?.backgroundColor = palette.background.cgColor
        layer?.borderColor = palette.border.cgColor
        dot.layer?.backgroundColor = palette.dot.cgColor
        label.attributedStringValue = Theme.attributed(
            pill.label, font: Theme.sans(14, weight: .medium), color: palette.ink)
        pulse(pill.tone == .listening)
        toolTip = pill.isActionable ? "Open Privacy Settings" : nil
    }

    private static func palette(for tone: WindowPresentation.Tone)
        -> (background: NSColor, border: NSColor, dot: NSColor, ink: NSColor) {
        switch tone {
        case .ready: return (Theme.greenBg, Theme.greenBorder, Theme.green, Theme.greenInk)
        case .working: return (Theme.workingBg, Theme.workingBorder, Theme.muted2, Theme.ink3)
        // An error wears the listening palette: the same warmth, a different word.
        case .listening, .blocked:
            return (Theme.clayBg, Theme.clayBorder, Theme.clay, Theme.clayHover)
        }
    }

    /// The dot breathes while the microphone is open, and only then.
    private func pulse(_ on: Bool) {
        guard on else {
            dot.layer?.removeAnimation(forKey: "breath")
            return
        }
        guard dot.layer?.animation(forKey: "breath") == nil else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 1
        breath.toValue = 0.45
        breath.duration = 0.7
        breath.autoreverses = true
        breath.repeatCount = .greatestFiniteMagnitude
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(breath, forKey: "breath")
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
