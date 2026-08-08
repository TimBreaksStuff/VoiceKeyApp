import Testing
import VoiceKeyCore

@Suite struct TranscriptCleanerTests {

    // MARK: - Filler removal

    @Test func removesStandaloneFillersAlongWithTheirTrailingComma() {
        // A filler swallows the comma that directly follows it; the punctuation
        // that belonged to the surrounding sentence is left alone.
        #expect(
            TranscriptCleaner.clean("So, um, I think we should, uh, ship it.")
                == "So, I think we should, ship it."
        )
    }

    @Test func removesFillersRegardlessOfCase() {
        #expect(TranscriptCleaner.clean("I UH think Er so") == "I think so")
        #expect(TranscriptCleaner.clean("Well Umm maybe Mhm later") == "Well maybe later")
    }

    @Test func removesEveryRecognisedFillerSpelling() {
        #expect(
            TranscriptCleaner.clean("one um two uh three uhm four umm five er six erm seven mhm eight")
                == "one two three four five six seven eight"
        )
    }

    @Test func removesFillerTogetherWithATrailingEllipsis() {
        #expect(TranscriptCleaner.clean("Well um ... maybe later") == "Well maybe later")
        #expect(TranscriptCleaner.clean("Well uh… maybe later") == "Well maybe later")
    }

    @Test func leavesWordsThatMerelyContainFillerSubstringsIntact() {
        #expect(
            TranscriptCleaner.clean("The umbrella and her summer termite.")
                == "The umbrella and her summer termite."
        )
    }

    @Test func leavesAnAlreadyCleanTranscriptUnchanged() {
        #expect(
            TranscriptCleaner.clean("The quick brown fox jumps over the lazy dog.")
                == "The quick brown fox jumps over the lazy dog."
        )
    }

    // MARK: - Sentence-start fillers

    @Test func capitalisesTheFollowingWordWhenAFillerOpensASentence() {
        #expect(TranscriptCleaner.clean("Um, hello there.") == "Hello there.")
        #expect(TranscriptCleaner.clean("I said no. Uh, maybe later.") == "I said no. Maybe later.")
    }

    @Test func sentenceStartCapitalisationUppercasesCamelCasedWordsToo() {
        // Accepted edge case: the rule cannot know that "iPhone" is deliberately
        // lowercase, so it becomes "IPhone". Not special-cased on purpose.
        #expect(TranscriptCleaner.clean("Um, iPhone users complain.") == "IPhone users complain.")
    }

    @Test func sentenceStartFillerIsStillRemovedWhenTheFollowingWordIsAlreadyCapitalised() {
        #expect(TranscriptCleaner.clean("Um, I think so.") == "I think so.")
    }

    // MARK: - Stumble collapse

    @Test func collapsesImmediateWordRepetitions() {
        #expect(TranscriptCleaner.clean("the the report") == "the report")
        #expect(TranscriptCleaner.clean("I I think so") == "I think so")
    }

    @Test func collapsesRepetitionsCaseInsensitivelyKeepingTheFirstSpelling() {
        #expect(TranscriptCleaner.clean("The the report") == "The report")
    }

    @Test func collapsesRunsOfMoreThanTwoRepetitions() {
        #expect(TranscriptCleaner.clean("It was very very very good") == "It was very good")
    }

    @Test func collapsesRepetitionsThatOnlyAppearAfterFillerRemoval() {
        #expect(TranscriptCleaner.clean("the um the report") == "the report")
    }

    @Test func doesNotCollapseRepetitionsSeparatedByPunctuation() {
        #expect(TranscriptCleaner.clean("No, no, never.") == "No, no, never.")
        #expect(TranscriptCleaner.clean("Stop. Stop now.") == "Stop. Stop now.")
    }

    @Test func collapsesLegitimateDoubledWordsAsAnAcceptedTradeoff() {
        // "had had" is grammatical, but bare adjacent repeats are collapsed
        // unconditionally — mis-collapsing this is preferred over keeping stutters.
        #expect(TranscriptCleaner.clean("She had had enough") == "She had enough")
    }

    // MARK: - Whitespace

    @Test func normalisesWhitespaceRunsAndTrimsTheResult() {
        #expect(TranscriptCleaner.clean("  Hello    world  ") == "Hello world")
        #expect(TranscriptCleaner.clean("Hello\tworld") == "Hello world")
    }

    @Test func returnsEmptyStringForBlankInput() {
        #expect(TranscriptCleaner.clean("") == "")
        #expect(TranscriptCleaner.clean("   ") == "")
        #expect(TranscriptCleaner.clean(" \n\t ") == "")
    }

    @Test func preservesNewlinesSoParagraphStructureSurvives() {
        #expect(
            TranscriptCleaner.clean("First line um  \n  Second   line")
                == "First line\nSecond line"
        )
        // A word ending one line and opening the next is not a stutter — collapsing
        // it would silently swallow the line break.
        #expect(TranscriptCleaner.clean("Send it\nit was fine") == "Send it\nit was fine")
    }

    // MARK: - Non-speech annotations

    @Test func identifiesTranscriptsThatAreEntirelyANonSpeechAnnotation() {
        #expect(TranscriptCleaner.isNonSpeechAnnotation("[wind howling]"))
        #expect(TranscriptCleaner.isNonSpeechAnnotation("(music)"))
        #expect(TranscriptCleaner.isNonSpeechAnnotation("[BLANK_AUDIO]"))
        #expect(TranscriptCleaner.isNonSpeechAnnotation("  [music]  "))
    }

    @Test func rejectsTranscriptsThatAreNotPurelyAnAnnotation() {
        #expect(!TranscriptCleaner.isNonSpeechAnnotation("Hello there."))
        #expect(!TranscriptCleaner.isNonSpeechAnnotation(""))
        #expect(!TranscriptCleaner.isNonSpeechAnnotation("   "))
        #expect(!TranscriptCleaner.isNonSpeechAnnotation("Hello [music] there"))
        #expect(!TranscriptCleaner.isNonSpeechAnnotation("[music] and then talking"))
        #expect(!TranscriptCleaner.isNonSpeechAnnotation("[]"))
    }
}
