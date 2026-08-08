import AppKit
import VoiceKeyCore

/// The library: an optional getting-started strip, the scrolling transcript list
/// — days newest first, every row carrying its own Copy / Insert / ⋯ actions —
/// and the status bar that says what is stored and where.
final class TranscriptsPane {

    enum Action {
        case copy(String)
        case addTerm(String)
        case delete(Transcript.ID)
        case undoDelete
        case deleteAll
        case exportAll
        case dismissOnboarding
        case changeShortcut
        /// Opens the window's help popover beside the control that asked for it.
        case showHelp(NSView)
    }

    let view = NSStackView()

    private let listArea = NSView()
    private let scroll = NSScrollView()
    private let stack = FlippedStackView()
    private let emptyTitle = Theme.label("", font: Theme.serif(22), color: Theme.ink3)
    private let emptyHint = Theme.label("", font: Theme.mono(12), color: Theme.muted3)
    private let emptyState = NSStackView()
    private let toast = ToastView()
    private let storageLine = Theme.label("", font: Theme.mono(11), color: Theme.muted3)
    private let statusBar = NSView()
    private let deleteAllLink: SidebarLink
    private var strip: OnboardingStripView?

    private let onAction: (Action) -> Void
    private var model = MainWindowModel()
    private var query = ""
    private var sort: TranscriptList.Sort = .newest
    private var rowViews: [TranscriptRowView] = []

    /// The page gutter — every band in the list lines up on it.
    private static let gutter: CGFloat = 32

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        self.deleteAllLink = SidebarLink(title: "Delete all transcripts",
                                         color: Theme.clay, hover: Theme.clayHover) {
            onAction(.deleteAll)
        }

        makeList()
        makeEmptyState()
        makeStatusBar()

        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 0
        addBand(listArea)
        addBand(statusBar)
        listArea.setContentHuggingPriority(.init(1), for: .vertical)
    }

    /// Every band spans the pane. A stack's `.width` alignment only makes its
    /// arranged views equal to *each other*, not to the stack — left to that,
    /// the list shrinks to its widest transcript and sits against the right edge.
    private func addBand(_ band: NSView, at index: Int? = nil) {
        if let index {
            view.insertArrangedSubview(band, at: index)
        } else {
            view.addArrangedSubview(band)
        }
        band.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    // MARK: - Input from the window

    func apply(_ model: MainWindowModel, rebuildList: Bool) {
        self.model = model
        syncStrip()
        storageLine.attributedStringValue = Theme.attributed(
            TranscriptList.storageLine(count: model.history.records.count),
            font: Theme.mono(11), color: Theme.muted3)
        deleteAllLink.isHidden = model.history.isEmpty
        if rebuildList { rebuild() }
    }

    /// The search box lives in the window header; this is what it types.
    func setQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        rebuild()
    }

    // MARK: - Onboarding

    private func syncStrip() {
        guard model.showsOnboarding else {
            strip?.removeFromSuperview()
            strip = nil
            return
        }
        if let strip {
            strip.shortcut = model.shortcut
            return
        }
        let block = OnboardingStripView(shortcut: model.shortcut, gutter: Self.gutter,
                                        onAction: onAction)
        strip = block
        addBand(block, at: 0)
    }

    // MARK: - The list

    private func makeList() {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        // Overlay whatever the system setting is: a legacy scroller would take
        // its width out of the content and pull the list off the header's grid.
        scroll.scrollerStyle = .overlay
        scroll.documentView = stack
        scroll.contentView.postsBoundsChangedNotifications = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listArea.addSubview(scroll)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: listArea.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listArea.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: listArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listArea.trailingAnchor),
        ])

        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.isHidden = true
        listArea.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: listArea.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: listArea.bottomAnchor, constant: -24),
        ])
        toast.onUndo = { [weak self] in
            self?.onAction(.undoDelete)
            self?.toast.dismiss()
        }
    }

    private func makeEmptyState() {
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 10
        emptyState.addArrangedSubview(emptyTitle)
        emptyState.addArrangedSubview(emptyHint)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        listArea.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: listArea.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: listArea.centerYAnchor),
        ])
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews = []

        let list = TranscriptList.make(from: model.history.records, query: query, sort: sort)
        showEmptyState(list.isEmpty)
        guard !list.isEmpty else { return }

        for (index, group) in list.groups.enumerated() {
            add(GroupHeadingView(group: group, gutter: Self.gutter,
                                 topSpacing: index == 0 ? 22 : 26,
                                 sortControl: index == 0 ? makeSortControl() : nil))
            for row in group.rows {
                let rowView = TranscriptRowView(row: row, gutter: Self.gutter,
                                                onAction: onAction,
                                                onDelete: { [weak self] in self?.deleted() },
                                                onArm: { [weak self] in self?.armedDelete() },
                                                onMove: { [weak self] step, from in
                                                    self?.moveFocus(step, from: from)
                                                })
                rowViews.append(rowView)
                add(rowView)
            }
        }
    }

    private func showEmptyState(_ isEmpty: Bool) {
        emptyState.isHidden = !isEmpty
        guard isEmpty else { return }
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        emptyTitle.attributedStringValue = Theme.attributed(
            searching ? "No transcripts match “\(needle)”" : "Nothing dictated yet",
            font: Theme.serif(22), color: Theme.ink3)
        emptyHint.attributedStringValue = Theme.attributed(
            searching ? "Press Esc to clear the search."
                : "Hold \(model.shortcut) in any window to start.",
            font: Theme.mono(12), color: Theme.muted3)
    }

    /// Every band spans the window: a row's columns sit on one grid, and its
    /// hover fill reaches the edges.
    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeSortControl() -> NSView {
        SortControl(title: Self.sortLabel(sort)) { [weak self] anchor in
            guard let self else { return }
            let menu = NSMenu()
            for option in [TranscriptList.Sort.newest, .oldest, .longest] {
                let item = ClosureMenuItem(title: Self.sortLabel(option)) { [weak self] in
                    guard let self, self.sort != option else { return }
                    self.sort = option
                    self.rebuild()
                }
                item.state = option == self.sort ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
        }
    }

    private static func sortLabel(_ sort: TranscriptList.Sort) -> String {
        switch sort {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .longest: return "Longest"
        }
    }

    // MARK: - Row focus and deletion

    private func moveFocus(_ step: Int, from row: TranscriptRowView) {
        guard let index = rowViews.firstIndex(where: { $0 === row }) else { return }
        let next = index + step
        guard rowViews.indices.contains(next) else { return }
        row.window?.makeFirstResponder(rowViews[next])
    }

    private func deleted() {
        toast.show(message: "Transcript deleted", undoable: true)
    }

    private func armedDelete() {
        toast.show(message: "Click “Delete again” to remove this transcript",
                   undoable: false, duration: TranscriptRowView.armedFor)
    }

    // MARK: - Status bar

    private func makeStatusBar() {
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = Theme.paperSunken.cgColor

        let rule = Theme.rule(Theme.borderSoft)
        let export = SidebarLink(title: "Export all") { [weak self] in self?.onAction(.exportAll) }
        let links = NSStackView(views: [export, deleteAllLink])
        links.orientation = .horizontal
        links.alignment = .centerY
        links.spacing = 18

        [rule, storageLine, links].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            statusBar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            statusBar.heightAnchor.constraint(equalToConstant: 52),
            rule.topAnchor.constraint(equalTo: statusBar.topAnchor),
            rule.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),

            storageLine.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor,
                                                 constant: Self.gutter),
            storageLine.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            links.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor,
                                            constant: -Self.gutter),
            links.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            links.leadingAnchor.constraint(greaterThanOrEqualTo: storageLine.trailingAnchor,
                                           constant: 20),
        ])
    }
}

/// Vertical stacks in a scroll view have to be flipped, or the content sits at
/// the bottom and scrolls the wrong way.
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - Onboarding

/// A strip that keeps the keycap visible, not a screenful.
final class OnboardingStripView: NSView {

    var shortcut: String {
        didSet {
            guard shortcut != oldValue else { return }
            keycap.text = shortcut
        }
    }

    private let keycap: KeycapView

    init(shortcut: String, gutter: CGFloat, onAction: @escaping (TranscriptsPane.Action) -> Void) {
        self.shortcut = shortcut
        self.keycap = KeycapView(text: shortcut)
        super.init(frame: .zero)

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.strip.cgColor
        card.layer?.borderColor = Theme.stripBorder.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 12

        let copy = WrappingLabel(attributed: Theme.attributed(
            "Hold anywhere in macOS and speak. On release VoiceKey types the text into "
                + "whatever has focus — dictionary spellings and punctuation already applied.",
            font: Theme.sans(15), color: Theme.ink2, lineHeight: 1.4))

        let show = SquareButton(title: "Show me how", filled: true) { button in
            onAction(.showHelp(button))
        }
        let change = SquareButton(title: "Change shortcut", filled: false) { _ in
            onAction(.changeShortcut)
        }
        let dismiss = GlyphButton(glyph: "✕") { onAction(.dismissOnboarding) }

        let buttons = NSStackView(views: [show, change, dismiss])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        // Pinned on both sides, like a row's actions: hug, or the slack between
        // the copy and the card's edge is taken here.
        buttons.setHuggingPriority(.required, for: .horizontal)

        [keycap, copy, buttons].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: gutter),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gutter),

            keycap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            keycap.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            keycap.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 16),

            copy.leadingAnchor.constraint(equalTo: keycap.trailingAnchor, constant: 20),
            copy.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            copy.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 16),
            copy.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),

            buttons.leadingAnchor.constraint(equalTo: copy.trailingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            buttons.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 16),
            buttons.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// The shortcut as a physical key: paper, a hard 1.5pt edge underneath.
final class KeycapView: NSView {
    var text: String {
        didSet { label.attributedStringValue = Self.styled(text) }
    }

    private let label: NSTextField

    init(text: String) {
        self.text = text
        self.label = NSTextField(labelWithAttributedString: Self.styled(text))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = Theme.keycapEdge.cgColor
        layer?.backgroundColor = Theme.paper.cgColor
        layer?.shadowColor = Theme.keycapEdge.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 0

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func styled(_ text: String) -> NSAttributedString {
        Theme.attributed(text, font: Theme.mono(14), color: Theme.ink())
    }
}

// MARK: - Buttons

/// The handoff's 8pt-cornered button, filled or outlined.
final class SquareButton: NSView {
    private let action: (NSView) -> Void
    private let filled: Bool
    private var hovering = false

    init(title: String, filled: Bool, action: @escaping (NSView) -> Void) {
        self.action = action
        self.filled = filled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        let label = Theme.label(title, font: Theme.sans(14, weight: filled ? .medium : .regular),
                                color: filled ? Theme.paper : Theme.ink2)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
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
    override func mouseUp(with event: NSEvent) { action(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func restyle() {
        layer?.backgroundColor = filled
            ? (hovering ? Theme.inkHover : Theme.ink()).cgColor
            : nil
        layer?.borderColor = filled
            ? (hovering ? Theme.inkHover : Theme.ink()).cgColor
            : (hovering ? Theme.ink() : Theme.keycapEdge).cgColor
    }
}

/// A "Copy" or "Delete" pill on a transcript row: visible at rest, by design.
/// The old build revealed them on hover and made the action invisible.
final class RowButton: NSView {
    /// Quiet like Copy and Insert, destructive, or armed and waiting for the
    /// second click that acts.
    enum Tone { case normal, destructive, armed }

    private let action: () -> Void
    private let label: NSTextField
    private var hovering = false

    var title: String { didSet { restyle() } }
    var tone: Tone { didSet { restyle() } }

    init(title: String, tone: Tone = .normal, action: @escaping () -> Void) {
        self.action = action
        self.title = title
        self.tone = tone
        self.label = Theme.label(title, font: Theme.sans(12.5), color: Theme.ink3)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
        let palette = colours()
        layer?.backgroundColor = palette.background.cgColor
        layer?.borderColor = palette.border.cgColor
        label.attributedStringValue = Theme.attributed(title, font: Theme.sans(12.5),
                                                       color: palette.ink)
    }

    private func colours() -> (background: NSColor, border: NSColor, ink: NSColor) {
        switch tone {
        case .normal:
            return (Theme.paper, hovering ? Theme.ink() : Theme.border,
                    hovering ? Theme.ink() : Theme.ink3)
        case .destructive:
            return (Theme.paper, hovering ? Theme.clay : Theme.border,
                    hovering ? Theme.clayHover : Theme.clay)
        case .armed:
            let fill = hovering ? Theme.clayHover : Theme.clay
            return (fill, fill, Theme.paper)
        }
    }
}

/// The "⋯" overflow on a row, and the "✕" that dismisses the strip.
final class GlyphButton: NSView {
    /// A var, so a row can point its "···" at a menu it can only build once it exists.
    var action: () -> Void
    private let glyph: String
    private let label: NSTextField

    init(glyph: String, action: @escaping () -> Void = {}) {
        self.action = action
        self.glyph = glyph
        self.label = Theme.label(glyph, font: Theme.mono(13), color: Theme.muted4)
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
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

    override func mouseEntered(with event: NSEvent) { recolour(Theme.ink()) }
    override func mouseExited(with event: NSEvent) { recolour(Theme.muted4) }
    override func mouseUp(with event: NSEvent) { action() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func recolour(_ colour: NSColor) {
        label.attributedStringValue = Theme.attributed(glyph, font: Theme.mono(13), color: colour)
    }
}

/// "Newest first ▾" — one control for the whole list, on the first group only.
final class SortControl: NSView {
    private let action: (NSView) -> Void
    private let title: String
    private let label: NSTextField

    init(title: String, action: @escaping (NSView) -> Void) {
        self.action = action
        self.title = title + " ▾"
        self.label = Theme.label(title + " ▾", font: Theme.sans(13), color: Theme.ink3)
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
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

    override func mouseEntered(with event: NSEvent) { recolour(Theme.ink()) }
    override func mouseExited(with event: NSEvent) { recolour(Theme.ink3) }
    override func mouseUp(with event: NSEvent) { action(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func recolour(_ colour: NSColor) {
        label.attributedStringValue = Theme.attributed(title, font: Theme.sans(13), color: colour)
    }
}

// MARK: - The list

/// "TODAY   4 transcripts · 39 words   Newest first ▾"
final class GroupHeadingView: NSView {
    init(group: TranscriptList.Group, gutter: CGFloat, topSpacing: CGFloat,
         sortControl: NSView?) {
        super.init(frame: .zero)
        let label = Theme.sectionLabel(group.label, size: 11)
        let meta = Theme.label(group.meta, font: Theme.mono(11), color: Theme.muted3)

        let trailing = NSStackView(views: sortControl.map { [meta, $0] } ?? [meta])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 18

        [label, trailing].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: topSpacing),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: gutter),

            trailing.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gutter),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor,
                                              constant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// One transcript: time, text, and the actions — visible at rest, not on hover.
final class TranscriptRowView: NSView {

    /// How long the "Copied" confirmation replaces the word count.
    private static let copiedFor: TimeInterval = 1.6

    private let gutter: CGFloat
    private let row: TranscriptList.Row
    private let onAction: (TranscriptsPane.Action) -> Void
    private let onDelete: () -> Void
    private let onMove: (Int, TranscriptRowView) -> Void
    /// How long a delete stays armed after the first click. The pane reads it
    /// too, so its "click again" toast lasts exactly as long as the arming.
    static let armedFor: TimeInterval = 4

    private let words: NSTextField
    private var deleteButton: RowButton!
    private var hovering = false { didSet { needsDisplay = true } }
    private var restoreWords: DispatchWorkItem?
    private var armed = false
    private var lapse: DispatchWorkItem?
    private let onArm: () -> Void

    init(row: TranscriptList.Row, gutter: CGFloat,
         onAction: @escaping (TranscriptsPane.Action) -> Void,
         onDelete: @escaping () -> Void,
         onArm: @escaping () -> Void,
         onMove: @escaping (Int, TranscriptRowView) -> Void) {
        self.gutter = gutter
        self.row = row
        self.onAction = onAction
        self.onDelete = onDelete
        self.onArm = onArm
        self.onMove = onMove
        self.words = Theme.label(row.words, font: Theme.tabular(Theme.mono(11)),
                                 color: Theme.muted4, alignment: .right)
        super.init(frame: .zero)
        deleteButton = RowButton(title: "Delete", tone: .destructive) { [weak self] in
            self?.pressDelete()
        }

        let time = Theme.label(row.time, font: Theme.tabular(Theme.mono(12)), color: Theme.muted3)
        let text = Theme.label(row.text, font: Theme.serif(18))
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copyButton = RowButton(title: "Copy") { [weak self] in self?.copyRow() }

        let actions = NSStackView(views: [words, copyButton, deleteButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        // The row pins the text's trailing edge to this stack and this stack to
        // the row's own. A stack hugs its content at .defaultLow, a label at
        // .defaultHigh, so the slack between them lands here unless it is said
        // otherwise — the buttons end up beside the text instead of at the edge.
        actions.setHuggingPriority(.required, for: .horizontal)

        [time, text, actions].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            // Wide enough for "2,140 words" — a fixed slot, so the buttons beside
            // it line up down the list however long the count runs.
            words.widthAnchor.constraint(equalToConstant: 84),

            time.leadingAnchor.constraint(equalTo: leadingAnchor, constant: gutter + 12),
            time.widthAnchor.constraint(equalToConstant: 78),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),

            // The time is a 78pt column, not a 78pt label with a gap after it —
            // the text starts where that column ends, as it does on Windows.
            text.leadingAnchor.constraint(equalTo: time.trailingAnchor),
            text.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -24),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(gutter + 12)),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Actions

    /// The confirmation lands on the row itself, where the click was — the word
    /// count steps aside for a beat and comes back.
    private func copyRow() {
        onAction(.copy(row.text))
        restoreWords?.cancel()
        words.attributedStringValue = Theme.attributed("Copied", font: Theme.mono(11),
                                                       color: Theme.green, alignment: .right)
        let restore = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.words.attributedStringValue = Theme.attributed(
                self.row.words, font: Theme.tabular(Theme.mono(11)),
                color: Theme.muted4, alignment: .right)
        }
        restoreWords = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFor, execute: restore)
    }

    /// Deleting takes two clicks. The first arms the button and says so in the
    /// toast; the second acts. A transcript is gone from `history.json` the
    /// moment it goes, so a stray click must not be enough — and the arming
    /// lapses on its own, so a forgotten one cannot lie in wait.
    private func pressDelete() {
        guard !armed else {
            disarmDelete()
            deleteRow()
            return
        }
        armed = true
        deleteButton.title = "Delete again"
        deleteButton.tone = .armed
        onArm()

        lapse?.cancel()
        let lapsing = DispatchWorkItem { [weak self] in self?.disarmDelete() }
        lapse = lapsing
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.armedFor, execute: lapsing)
    }

    private func disarmDelete() {
        lapse?.cancel()
        armed = false
        deleteButton.title = "Delete"
        deleteButton.tone = .destructive
    }

    private func deleteRow() {
        onAction(.delete(row.id))
        onDelete()
    }

    // MARK: - Hover and focus

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow,
                                                 .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    /// Enter copies, ⌘Enter inserts, Delete deletes, ↑/↓ walk the list.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: copyRow()
        case 51, 117: pressDelete()
        case 125: onMove(1, self)
        case 126: onMove(-1, self)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // the hover fill bleeds to the window edges; the rule keeps to the grid
        if hovering || window?.firstResponder === self {
            Theme.field.setFill()
            bounds.fill()
        }
        Theme.borderRow.setFill()
        NSRect(x: gutter, y: 0, width: max(0, bounds.width - gutter * 2), height: 1).fill()
        guard window?.firstResponder === self else { return }
        Theme.ink(0.24).setStroke()
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: gutter, dy: 2),
                                xRadius: 8, yRadius: 8)
        ring.lineWidth = 2
        ring.stroke()
    }
}

/// An in-window confirmation; fades itself out, and carries the undo.
final class ToastView: NSView {
    var onUndo: (() -> Void)?

    private let label = Theme.label("", font: Theme.sans(14), color: Theme.paper)
    private var undo: SidebarLink!
    private var hide: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        undo = SidebarLink(title: "Undo", color: Theme.greenMeta, hover: Theme.paper) {
            [weak self] in self?.onUndo?()
        }

        wantsLayer = true
        layer?.backgroundColor = Theme.ink().cgColor
        layer?.cornerRadius = 9

        let row = NSStackView(views: [label, undo])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(message: String, undoable: Bool, duration: TimeInterval? = nil) {
        label.attributedStringValue = Theme.attributed(message, font: Theme.sans(14),
                                                       color: Theme.paper)
        undo.isHidden = !undoable
        isHidden = false
        alphaValue = 1

        hide?.cancel()
        // An undo needs long enough to be read and reached; a plain note does not.
        let dismissal = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration ?? (undoable ? 6 : 2)),
                                      execute: dismissal)
    }

    func dismiss() {
        hide?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
        })
    }
}

/// An NSMenuItem that runs a closure — these menus have no shared target.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}
