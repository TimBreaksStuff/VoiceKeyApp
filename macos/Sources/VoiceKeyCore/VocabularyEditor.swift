import Foundation

/// The dictionary as an editable list of rows — what the Dictionary window shows
/// and edits, and the only place that knows how rows become a `VocabularyDictionary`.
///
/// Rows exist because `VocabularyDictionary.replacements` is an unordered map: a
/// table needs stable positions, and a row being edited is allowed to be blank or
/// duplicated for as long as the user is typing. Nothing invalid reaches disk —
/// `dictionary` is the filter.
public struct VocabularyEditor: Equatable {

    /// One "when I say X, type Y" row. Either half may be blank while editing.
    public struct Replacement: Equatable {
        public var spoken: String
        public var written: String

        public init(spoken: String = "", written: String = "") {
            self.spoken = spoken
            self.written = written
        }

        var isComplete: Bool { !spoken.trimmed.isEmpty && !written.trimmed.isEmpty }
    }

    public let replacements: [Replacement]
    public let terms: [String]

    public init(dictionary: VocabularyDictionary = VocabularyDictionary()) {
        self.replacements = dictionary.replacements
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { Replacement(spoken: $0.key, written: $0.value) }
        self.terms = dictionary.terms
    }

    private init(replacements: [Replacement], terms: [String]) {
        self.replacements = replacements
        self.terms = terms
    }

    /// The saveable dictionary: blank halves and rows shadowed by an earlier row
    /// with the same spoken phrase are dropped, so what the user sees first wins.
    public var dictionary: VocabularyDictionary {
        let ignored = ignoredReplacementRows
        let rules = replacements.enumerated()
            .filter { $0.element.isComplete && !ignored.contains($0.offset) }
            .reduce(into: [String: String]()) { result, entry in
                result[entry.element.spoken.trimmed] = entry.element.written.trimmed
            }
        return VocabularyDictionary(terms: terms.map(\.trimmed).filter { !$0.isEmpty },
                                    replacements: rules)
    }

    /// Rows that will not take effect because an earlier row already claims the
    /// same spoken phrase — matching is case-insensitive, so replacing is too.
    public var ignoredReplacementRows: IndexSet {
        var claimed = Set<String>()
        return replacements.enumerated().reduce(into: IndexSet()) { ignored, entry in
            let spoken = entry.element.spoken.trimmed.lowercased()
            guard !spoken.isEmpty else { return }
            if !claimed.insert(spoken).inserted { ignored.insert(entry.offset) }
        }
    }

    // MARK: - Editing

    public func addingReplacement() -> VocabularyEditor {
        VocabularyEditor(replacements: replacements + [Replacement()], terms: terms)
    }

    public func settingSpoken(_ text: String, at index: Int) -> VocabularyEditor {
        updatingReplacement(at: index) { $0.spoken = text }
    }

    public func settingWritten(_ text: String, at index: Int) -> VocabularyEditor {
        updatingReplacement(at: index) { $0.written = text }
    }

    public func removingReplacements(at indexes: IndexSet) -> VocabularyEditor {
        VocabularyEditor(replacements: replacements.removing(indexes), terms: terms)
    }

    public func addingTerm() -> VocabularyEditor {
        VocabularyEditor(replacements: replacements, terms: terms + [""])
    }

    public func settingTerm(_ text: String, at index: Int) -> VocabularyEditor {
        guard terms.indices.contains(index) else { return self }
        var updated = terms
        updated[index] = text
        return VocabularyEditor(replacements: replacements, terms: updated)
    }

    public func removingTerms(at indexes: IndexSet) -> VocabularyEditor {
        VocabularyEditor(replacements: replacements, terms: terms.removing(indexes))
    }

    private func updatingReplacement(
        at index: Int,
        _ edit: (inout Replacement) -> Void
    ) -> VocabularyEditor {
        guard replacements.indices.contains(index) else { return self }
        var updated = replacements
        edit(&updated[index])
        return VocabularyEditor(replacements: updated, terms: terms)
    }
}

private extension Array {
    func removing(_ indexes: IndexSet) -> [Element] {
        enumerated().filter { !indexes.contains($0.offset) }.map(\.element)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
