import Testing
// Foundation deliberately not imported here — it reaches this file through
// FoundationExport.swift. See that file for why a direct import cannot work.
@testable import VoiceKeyCore

@Suite struct VocabularyDictionaryTests {

    // MARK: - Replacements

    @Test func replacementMatchesWholeWordCaseInsensitively() {
        let dictionary = makeDictionary(replacements: ["get hub": "GitHub"])

        #expect(
            dictionary.applyingReplacements(to: "I pushed to get hub today")
                == "I pushed to GitHub today"
        )
        #expect(
            dictionary.applyingReplacements(to: "Get hub is down.")
                == "GitHub is down."
        )
    }

    @Test func replacementDoesNotMatchInsideLargerWord() {
        let dictionary = makeDictionary(replacements: ["get hub": "GitHub"])

        #expect(
            dictionary.applyingReplacements(to: "a target hubcap")
                == "a target hubcap"
        )
    }

    @Test func multiWordPhraseKeyIsReplaced() {
        let dictionary = makeDictionary(replacements: ["large language model": "LLM"])

        #expect(
            dictionary.applyingReplacements(to: "the large language model wrote it")
                == "the LLM wrote it"
        )
    }

    @Test func replacementValueKeepsItsOwnCasing() {
        let dictionary = makeDictionary(replacements: ["jason": "JSON"])

        #expect(
            dictionary.applyingReplacements(to: "Jason and jason")
                == "JSON and JSON"
        )
    }

    @Test func keysWithRegexMetacharactersAreTreatedLiterally() {
        let dictionary = makeDictionary(replacements: [
            "c++": "C++",
            "node.js": "Node.js",
        ])

        #expect(
            dictionary.applyingReplacements(to: "I write c++ and node.js")
                == "I write C++ and Node.js"
        )
        #expect(
            dictionary.applyingReplacements(to: "nodexjs stays")
                == "nodexjs stays"
        )
    }

    @Test func replacementOutputIsNeverRematchedByAnotherRule() {
        let dictionary = makeDictionary(replacements: ["alpha": "beta", "beta": "gamma"])

        #expect(
            dictionary.applyingReplacements(to: "alpha and beta")
                == "beta and gamma"
        )
    }

    @Test func longerKeyWinsOverOverlappingShorterKey() {
        let dictionary = makeDictionary(replacements: [
            "visual studio": "Visual Studio",
            "visual studio code": "VS Code",
        ])

        #expect(
            dictionary.applyingReplacements(to: "open visual studio code now")
                == "open VS Code now"
        )
        #expect(
            dictionary.applyingReplacements(to: "open visual studio now")
                == "open Visual Studio now"
        )
    }

    @Test func replacementSurvivesNonASCIITextAroundMatches() {
        let dictionary = makeDictionary(replacements: ["jason": "JSON"])

        #expect(
            dictionary.applyingReplacements(to: "🎤 jason, café jason — jason")
                == "🎤 JSON, café JSON — JSON"
        )
    }

    @Test func emptyReplacementsLeaveTextUnchanged() {
        let dictionary = makeDictionary()
        let text = "nothing to see here"

        #expect(dictionary.applyingReplacements(to: text) == text)
    }

    // MARK: - Prompt text

    @Test func promptTextIsNilWithoutTerms() {
        #expect(makeDictionary().promptText == nil)
    }

    @Test func promptTextIsSingleLineMentioningEveryTerm() throws {
        let terms = ["GitHub", "Kubernetes", "Herglotz"]
        let dictionary = makeDictionary(terms: terms)

        let prompt = try #require(dictionary.promptText, "expected a prompt for a non-empty term list")
        terms.forEach { #expect(prompt.contains($0), "prompt is missing term \($0)") }
        #expect(!prompt.contains("\n"), "prompt must stay on a single line")
    }

    // MARK: - Persistence

    @Test func loadReturnsNilForMissingFile() {
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(VocabularyDictionary.load(from: url) == nil)
    }

    @Test func loadReturnsNilForMalformedJSON() throws {
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ this is not json".utf8).write(to: url)

        #expect(VocabularyDictionary.load(from: url) == nil)
    }

    @Test func saveThenLoadRoundTripsTheDictionary() throws {
        let original = makeDictionary(
            terms: ["WhisperKit", "Herglotz"],
            replacements: ["get hub": "GitHub", "jason": "JSON"]
        )
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try original.save(to: url)

        #expect(VocabularyDictionary.load(from: url) == original)
    }

    @Test func savedFileIsPrettyPrintedWithSortedKeys() throws {
        let url = makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try makeDictionary(replacements: ["zebra": "Z", "alpha": "A"]).save(to: url)

        let json = try String(contentsOf: url, encoding: .utf8)

        #expect(json.contains("\n"), "expected pretty-printed JSON")
        #expect(json.contains("  "), "expected indentation")
        let alpha = try #require(json.range(of: "alpha"), "expected both replacement keys in \(json)")
        let zebra = try #require(json.range(of: "zebra"), "expected both replacement keys in \(json)")
        #expect(alpha.lowerBound < zebra.lowerBound, "expected sorted keys")
    }

    // MARK: - Template

    @Test func templateDocumentsTheSchemaByExample() {
        let template = VocabularyDictionary.template

        #expect(!template.terms.isEmpty, "template should show an example term")
        #expect(!template.replacements.isEmpty, "template should show an example replacement")
    }

    @Test func templateReplacementsActuallyApply() throws {
        let template = VocabularyDictionary.template

        let (spoken, written) = try #require(
            template.replacements.first,
            "template should show an example replacement"
        )
        #expect(template.applyingReplacements(to: spoken) == written)
    }

    // MARK: - Suggesting a term from a transcript

    @Test func aShortTranscriptIsOfferedAsATermReadyToKeep() {
        #expect(VocabularyDictionary.suggestedTerm(from: "Kubernetes") == "Kubernetes")
        #expect(VocabularyDictionary.suggestedTerm(from: "  Voice Key  ") == "Voice Key")
    }

    @Test func aSuggestedTermReadsAsOneLine() {
        #expect(VocabularyDictionary.suggestedTerm(from: "Voice\nKey") == "Voice Key")
    }

    @Test func aWholeSentenceIsNoTermSoNothingIsSuggested() {
        #expect(VocabularyDictionary.suggestedTerm(from: "Rebase onto main, then force push.") == nil)
        #expect(VocabularyDictionary.suggestedTerm(from: "   ") == nil)
    }

    // MARK: - Helpers

    private func makeDictionary(
        terms: [String] = [],
        replacements: [String: String] = [:]
    ) -> VocabularyDictionary {
        VocabularyDictionary(terms: terms, replacements: replacements)
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabularyDictionaryTests-\(UUID().uuidString).json")
    }
}
