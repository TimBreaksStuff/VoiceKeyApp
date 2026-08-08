import Foundation
import WhisperKit

/// WhisperKit wrapper. Adding a language later = change the model to a
/// multilingual one (e.g. distil-whisper_distil-large-v3_turbo_600MB) and
/// the language code below.
final class Transcriber {
    enum TranscribeError: Error { case notLoaded }

    static let modelName = "openai_whisper-small.en"
    static let language = "en"

    private var pipe: WhisperKit?

    /// Call once at app launch. First run downloads the model (~217MB) and
    /// specializes it for the ANE — 30s–2min, cached afterwards.
    func load() async throws {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceKey", isDirectory: true)
        // downloadBase override matters: WhisperKit's default lands in
        // ~/Documents, which triggers an extra macOS TCC prompt
        let config = WhisperKitConfig(model: Self.modelName, downloadBase: base)
        pipe = try await WhisperKit(config)
    }

    /// `vocabularyPrompt` biases recognition toward user vocabulary: WhisperKit
    /// prepends the encoded prompt as decoder conditioning (and strips any
    /// special tokens itself), so unusual names/jargon are spelled as listed.
    func transcribe(_ samples: [Float], vocabularyPrompt: String? = nil) async throws -> String {
        guard let pipe else { throw TranscribeError.notLoaded }
        let promptTokens = vocabularyPrompt.flatMap { prompt in
            pipe.tokenizer.map { $0.encode(text: " " + prompt) }
        }
        let options = DecodingOptions(language: Self.language, promptTokens: promptTokens)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
