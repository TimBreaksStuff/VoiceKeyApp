import AppKit
import VoiceKeyCore

/// The Dictionary pane: two editable tables — spoken phrase on the left,
/// written result on the right — plus the vocabulary terms that bias Whisper.
///
/// Every edit is written straight to `dictionary.json`; there is no Save button
/// because the next dictation reloads the file anyway. All row logic lives in
/// `VocabularyEditor`; this file is only AppKit glue.
final class DictionaryPane: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private enum Column {
        static let spoken = NSUserInterfaceItemIdentifier("spoken")
        static let written = NSUserInterfaceItemIdentifier("written")
        static let term = NSUserInterfaceItemIdentifier("term")
    }

    private let url: URL
    private var editor = VocabularyEditor()
    private let replacementsTable = NSTableView()
    private let termsTable = NSTableView()
    /// Kept so the two tables can share the spare height evenly.
    private var scrollViews: [NSScrollView] = []

    lazy var view: NSView = makeView()

    /// Told after every save, so the sidebar's entry count keeps up.
    var onSaved: (() -> Void)?

    /// How much the user has taught VoiceKey: terms plus replacement rules.
    var entryCount: Int {
        let dictionary = VocabularyDictionary.load(from: url) ?? VocabularyDictionary()
        return dictionary.terms.count + dictionary.replacements.count
    }

    init(url: URL) {
        self.url = url
    }

    /// Re-reads the file: it may have been edited by hand since the last look.
    func reload() {
        editor = VocabularyEditor(dictionary: VocabularyDictionary.load(from: url) ?? VocabularyDictionary())
        replacementsTable.reloadData()
        termsTable.reloadData()
    }

    /// Adds a vocabulary row and puts the cursor in it — how a transcript's
    /// "Add Term to Dictionary" lands here. A phrase short enough to be a term
    /// arrives already typed in.
    func addTerm(suggestion: String?) {
        commitEditing()
        editor = editor.addingTerm()
        if let suggestion {
            editor = editor.settingTerm(suggestion, at: editor.terms.count - 1)
        }
        save()
        termsTable.reloadData()
        beginEditingLastRow(of: termsTable)
    }

    // MARK: - Building the screen

    private func makeView() -> NSView {
        let replacements = section(
            title: "Replacements",
            subtitle: "Whisper hears the phrase on the left, VoiceKey types the text on the right.",
            table: configure(replacementsTable, columns: [
                (Column.spoken, "When I say", 240),
                (Column.written, "Type this", 240),
            ]),
            add: #selector(addReplacement), remove: #selector(removeReplacements))

        let terms = section(
            title: "Vocabulary",
            subtitle: "Names and jargon to expect — these bias recognition before any replacement runs.",
            table: configure(termsTable, columns: [(Column.term, "Term", 480)]),
            add: #selector(addTermRow), remove: #selector(removeTerms))

        let footer = Theme.label("Changes apply to your next dictation.",
                                 font: Theme.mono(11), color: Theme.ink(0.5))
        footer.setContentHuggingPriority(.required, for: .vertical)

        let stack = NSStackView(views: [replacements, terms, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 26
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 44),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -44),
            replacements.widthAnchor.constraint(equalTo: stack.widthAnchor),
            terms.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        if let first = scrollViews.first {
            scrollViews.dropFirst().forEach {
                $0.heightAnchor.constraint(equalTo: first.heightAnchor).isActive = true
            }
        }
        return container
    }

    /// Section label, one line of explanation, the table, and its +/− control.
    private func section(title: String, subtitle: String, table: NSView,
                         add: Selector, remove: Selector) -> NSView {
        let heading = Theme.sectionLabel(title)
        let explanation = Theme.label(subtitle, font: Theme.serif(15), color: Theme.ink(0.72))

        let buttons = NSSegmentedControl(
            images: [image(NSImage.addTemplateName), image(NSImage.removeTemplateName)],
            trackingMode: .momentary, target: self, action: #selector(segmentClicked(_:)))
        buttons.segmentStyle = .smallSquare
        buttons.setToolTip("Add a row", forSegment: 0)
        buttons.setToolTip("Remove the selected rows", forSegment: 1)
        buttons.setContentHuggingPriority(.required, for: .horizontal) // or it stretches to the table's width
        segmentActions[ObjectIdentifier(buttons)] = (add, remove)

        let stack = NSStackView(views: [heading, explanation, table, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: explanation)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        table.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// A segmented control has one action, so the +/− selectors are looked up per control.
    private var segmentActions: [ObjectIdentifier: (add: Selector, remove: Selector)] = [:]

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        guard let actions = segmentActions[ObjectIdentifier(sender)] else { return }
        NSApp.sendAction(sender.selectedSegment == 0 ? actions.add : actions.remove, to: self, from: sender)
    }

    private func image(_ name: String) -> NSImage {
        NSImage(named: name) ?? NSImage(size: NSSize(width: 12, height: 12))
    }

    private func configure(_ table: NSTableView,
                           columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)]) -> NSView {
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.style = .fullWidth
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical) // the tables take the spare height
        scrollViews.append(scroll)
        return scroll
    }

    // MARK: - Table contents

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === replacementsTable ? editor.replacements.count : editor.terms.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? makeField(identifier)
        field.stringValue = value(identifier, row: row)
        field.placeholderString = Self.placeholder(identifier)
        // A row shadowed by an earlier one with the same phrase is dead weight — say so.
        let ignored = tableView === replacementsTable && editor.ignoredReplacementRows.contains(row)
        field.textColor = ignored ? .tertiaryLabelColor : .labelColor
        field.toolTip = ignored ? "Ignored — an earlier row already uses this phrase." : nil
        return field
    }

    private func makeField(_ identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField()
        field.identifier = identifier
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.font = Theme.serif(13)
        field.lineBreakMode = .byTruncatingTail
        field.target = self
        field.action = #selector(fieldEdited(_:))
        field.cell?.sendsActionOnEndEditing = true // commit on Tab or focus loss, not only Return
        return field
    }

    private func value(_ identifier: NSUserInterfaceItemIdentifier, row: Int) -> String {
        switch identifier {
        case Column.spoken: return editor.replacements[row].spoken
        case Column.written: return editor.replacements[row].written
        default: return editor.terms[row]
        }
    }

    private static func placeholder(_ identifier: NSUserInterfaceItemIdentifier) -> String {
        switch identifier {
        case Column.spoken: return "get hub"
        case Column.written: return "GitHub"
        default: return "Kubernetes"
        }
    }

    // MARK: - Editing

    /// Fires when a field commits (Return, Tab or losing focus).
    @objc private func fieldEdited(_ sender: NSTextField) {
        let text = sender.stringValue
        let replacementRow = replacementsTable.row(for: sender)
        if replacementRow >= 0 {
            editor = sender.identifier == Column.spoken
                ? editor.settingSpoken(text, at: replacementRow)
                : editor.settingWritten(text, at: replacementRow)
        } else {
            let termRow = termsTable.row(for: sender)
            guard termRow >= 0 else { return }
            editor = editor.settingTerm(text, at: termRow)
        }
        save()
        restyleReplacementRows()
    }

    @objc private func addReplacement() {
        commitEditing()
        editor = editor.addingReplacement()
        save()
        replacementsTable.reloadData()
        beginEditingLastRow(of: replacementsTable)
    }

    @objc private func removeReplacements() {
        commitEditing()
        editor = editor.removingReplacements(at: replacementsTable.selectedRowIndexes)
        save()
        replacementsTable.reloadData()
    }

    @objc private func addTermRow() {
        addTerm(suggestion: nil)
    }

    @objc private func removeTerms() {
        commitEditing()
        editor = editor.removingTerms(at: termsTable.selectedRowIndexes)
        save()
        termsTable.reloadData()
    }

    /// The field being typed into still owns its text — force it to commit before
    /// rows move underneath it.
    func commitEditing() {
        view.window?.makeFirstResponder(nil)
    }

    private func beginEditingLastRow(of table: NSTableView) {
        let row = table.numberOfRows - 1
        guard row >= 0 else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        table.editColumn(0, row: row, with: nil, select: true)
    }

    /// Refresh the shadowed-row styling without reloading, which would end editing.
    private func restyleReplacementRows() {
        let ignored = editor.ignoredReplacementRows
        for row in 0..<replacementsTable.numberOfRows {
            for column in 0..<replacementsTable.numberOfColumns {
                guard let field = replacementsTable.view(atColumn: column, row: row,
                                                         makeIfNecessary: false) as? NSTextField
                else { continue }
                field.textColor = ignored.contains(row) ? .tertiaryLabelColor : .labelColor
            }
        }
    }

    private func save() {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try editor.dictionary.save(to: url)
            Log.line("dictionary saved — \(editor.dictionary.terms.count) terms, "
                     + "\(editor.dictionary.replacements.count) replacements")
        } catch {
            Log.line("dictionary save FAILED: \(error)")
        }
        onSaved?()
    }
}
