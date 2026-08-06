import Foundation

/// User-editable custom vocabulary: terms that bias Whisper through an initial prompt,
/// plus spoken-to-written replacement rules applied to the finished transcript.
public struct VocabularyDictionary: Codable, Equatable {
    public var terms: [String]
    public var replacements: [String: String]

    public init(terms: [String] = [], replacements: [String: String] = [:]) {
        self.terms = terms
        self.replacements = replacements
    }

    /// Whisper initial-prompt text biasing recognition toward the terms, or nil when there are no terms.
    public var promptText: String? {
        let named = terms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !named.isEmpty else { return nil }
        return "Glossary: " + named.joined(separator: ", ") + "."
    }

    /// Applies every replacement rule in a single left-to-right pass, so a rule's output
    /// can never be rewritten by another rule. Longer keys win over overlapping shorter ones.
    public func applyingReplacements(to text: String) -> String {
        guard let matcher = Matcher(replacements: replacements) else { return text }
        return matcher.applied(to: text)
    }

    /// Starter content written on first use so the user edits a documented example.
    public static let template = VocabularyDictionary(
        terms: ["VoiceKey", "WhisperKit", "Kubernetes"],
        replacements: [
            "get hub": "GitHub",
            "jason": "JSON",
        ]
    )

    /// A transcript offered back as a vocabulary term, or nil when it is plainly
    /// a sentence rather than a name: terms bias recognition, and biasing towards
    /// a whole sentence would do more harm than good.
    public static func suggestedTerm(from transcript: String) -> String? {
        let words = transcript.split(whereSeparator: { $0.isWhitespace })
        guard (1...4).contains(words.count) else { return nil }
        let term = words.joined(separator: " ")
        guard term.count <= 40 else { return nil }
        return term
    }

    /// Reads JSON from disk; nil if the file is missing or malformed — a broken user edit
    /// must degrade to "no custom vocabulary", never crash the app.
    public static func load(from url: URL) -> VocabularyDictionary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VocabularyDictionary.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// One combined case-insensitive alternation over every rule key. Building a single
/// expression is what guarantees the single pass; ordering the alternatives longest-first
/// is what gives longer keys precedence.
private struct Matcher {
    private let expression: Regex<AnyRegexOutput>
    private let valuesByLowercasedKey: [String: String]

    init?(replacements: [String: String]) {
        let keys = replacements.keys
            .filter { !$0.isEmpty }
            .sorted { ($0.count, $0) > ($1.count, $1) }
        guard !keys.isEmpty else { return nil }

        let pattern = keys.map(Matcher.wholeWordPattern).joined(separator: "|")
        guard let expression = try? Regex(pattern).ignoresCase() else { return nil }
        self.expression = expression
        self.valuesByLowercasedKey = replacements.reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    func applied(to text: String) -> String {
        text.replacing(expression) { match in
            let matched = String(match.output[0].substring ?? "")
            return valuesByLowercasedKey[matched.lowercased()] ?? matched
        }
    }

    /// Escapes the key so metacharacters ("c++", "node.js") stay literal, and fences it with
    /// boundaries that adapt to the edge characters — `\b` only works next to word characters,
    /// so keys ending in punctuation get a "not followed by a word character" assertion instead.
    private static func wholeWordPattern(for key: String) -> String {
        let leading = key.first.map(isWordCharacter) == true ? #"\b"# : #"(?<!\w)"#
        let trailing = key.last.map(isWordCharacter) == true ? #"\b"# : #"(?!\w)"#
        return leading + NSRegularExpression.escapedPattern(for: key) + trailing
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
