import Testing
// Foundation deliberately not imported here — see FoundationExport.swift.
@testable import VoiceKeyCore

@Suite struct VocabularyEditorTests {

    // MARK: - Loading

    @Test func replacementRowsAreSortedBySpokenPhrase() {
        let editor = makeEditor(replacements: ["zebra": "Z", "alpha": "A", "middle": "M"])

        #expect(editor.replacements.map(\.spoken) == ["alpha", "middle", "zebra"])
        #expect(editor.replacements.map(\.written) == ["A", "M", "Z"])
    }

    @Test func termsKeepTheOrderTheyWereSavedIn() {
        let editor = makeEditor(terms: ["Kubernetes", "VoiceKey", "Herglotz"])

        #expect(editor.terms == ["Kubernetes", "VoiceKey", "Herglotz"])
    }

    @Test func anEmptyDictionaryOpensWithNoRows() {
        let editor = VocabularyEditor()

        #expect(editor.replacements.isEmpty)
        #expect(editor.terms.isEmpty)
    }

    // MARK: - Saving

    @Test func editedRowsRoundTripBackIntoTheDictionary() {
        let original = VocabularyDictionary(terms: ["WhisperKit"],
                                            replacements: ["get hub": "GitHub"])

        #expect(VocabularyEditor(dictionary: original).dictionary == original)
    }

    @Test func aHalfTypedRowIsNotSavedAsARule() {
        let editor = makeEditor(replacements: ["get hub": "GitHub"])
            .addingReplacement()
            .settingSpoken("jason", at: 1)

        #expect(editor.replacements.count == 2, "the half-typed row stays visible while editing")
        #expect(editor.dictionary.replacements == ["get hub": "GitHub"])
    }

    @Test func blankTermsAreNotSaved() {
        let editor = makeEditor(terms: ["VoiceKey"]).addingTerm()

        #expect(editor.terms.count == 2)
        #expect(editor.dictionary.terms == ["VoiceKey"])
    }

    @Test func surroundingWhitespaceIsTrimmedOnSave() {
        let editor = VocabularyEditor()
            .addingReplacement()
            .settingSpoken("  get hub  ", at: 0)
            .settingWritten("  GitHub  ", at: 0)
            .addingTerm()
            .settingTerm("  WhisperKit  ", at: 0)

        #expect(editor.dictionary.replacements == ["get hub": "GitHub"])
        #expect(editor.dictionary.terms == ["WhisperKit"])
    }

    @Test func theFirstOfTwoRowsWithTheSameSpokenPhraseWins() {
        let editor = VocabularyEditor()
            .addingReplacement()
            .settingSpoken("jason", at: 0)
            .settingWritten("JSON", at: 0)
            .addingReplacement()
            .settingSpoken("Jason", at: 1)
            .settingWritten("Jason Bourne", at: 1)

        #expect(editor.dictionary.replacements == ["jason": "JSON"],
                "the row shown first is the one that takes effect")
    }

    @Test func duplicateSpokenPhrasesAreFlaggedForTheUserCaseInsensitively() {
        let editor = VocabularyEditor()
            .addingReplacement()
            .settingSpoken("jason", at: 0)
            .settingWritten("JSON", at: 0)
            .addingReplacement()
            .settingSpoken(" JASON ", at: 1)
            .settingWritten("Jason Bourne", at: 1)
            .addingReplacement()
            .settingSpoken("get hub", at: 2)
            .settingWritten("GitHub", at: 2)

        #expect(editor.ignoredReplacementRows == [1],
                "only the shadowed row is flagged, not the one that takes effect")
    }

    @Test func emptyRowsAreNotFlaggedAsDuplicatesOfEachOther() {
        let editor = VocabularyEditor().addingReplacement().addingReplacement()

        #expect(editor.ignoredReplacementRows.isEmpty)
    }

    // MARK: - Editing

    @Test func addingAReplacementAppendsAnEmptyRowAtTheEnd() {
        let editor = makeEditor(replacements: ["get hub": "GitHub"]).addingReplacement()

        #expect(editor.replacements.count == 2)
        #expect(editor.replacements.last == VocabularyEditor.Replacement(spoken: "", written: ""))
    }

    @Test func editingOneRowLeavesTheOthersAlone() {
        let editor = makeEditor(replacements: ["alpha": "A", "beta": "B"])
            .settingWritten("Bravo", at: 1)

        #expect(editor.dictionary.replacements == ["alpha": "A", "beta": "Bravo"])
    }

    @Test func removingRowsDropsExactlyTheSelectedOnes() {
        let editor = makeEditor(replacements: ["alpha": "A", "beta": "B", "gamma": "G"])
            .removingReplacements(at: [0, 2])

        #expect(editor.dictionary.replacements == ["beta": "B"])
    }

    @Test func removingTermsDropsExactlyTheSelectedOnes() {
        let editor = makeEditor(terms: ["one", "two", "three"]).removingTerms(at: [1])

        #expect(editor.terms == ["one", "three"])
    }

    @Test func termsCanBeAddedAndEdited() {
        let editor = VocabularyEditor().addingTerm().settingTerm("Kubernetes", at: 0)

        #expect(editor.dictionary.terms == ["Kubernetes"])
    }

    @Test func editsToRowsThatDoNotExistAreIgnored() {
        let editor = makeEditor(replacements: ["alpha": "A"], terms: ["one"])

        #expect(editor.settingSpoken("x", at: 7) == editor)
        #expect(editor.settingWritten("x", at: -1) == editor)
        #expect(editor.settingTerm("x", at: 3) == editor)
        #expect(editor.removingReplacements(at: [9]) == editor)
        #expect(editor.removingTerms(at: [9]) == editor)
    }

    // MARK: - Helpers

    private func makeEditor(
        replacements: [String: String] = [:],
        terms: [String] = []
    ) -> VocabularyEditor {
        VocabularyEditor(dictionary: VocabularyDictionary(terms: terms, replacements: replacements))
    }
}
