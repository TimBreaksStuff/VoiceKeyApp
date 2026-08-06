import Testing
@testable import VoiceKeyCore

@Suite struct DictationModeTests {

    // MARK: - Dictating while VoiceKey itself is frontmost

    @Test func aDictationIsInsertedIntoWhateverOtherAppIsFrontmost() {
        #expect(DictationMode.insertsAtCursor(frontmostBundleID: "com.apple.TextEdit",
                                              ownBundleID: "com.timherglotz.voicekey"))
    }

    @Test func aDictationIsNotInsertedWhenVoiceKeyItselfIsFrontmost() {
        // Otherwise it lands in the window's own search field, which filters the
        // library down to the transcript just spoken — it reads as data loss.
        #expect(!DictationMode.insertsAtCursor(frontmostBundleID: "com.timherglotz.voicekey",
                                               ownBundleID: "com.timherglotz.voicekey"))
    }

    @Test func theFrontmostAppIsRecognisedWhateverCaseItReportsItsBundleIDIn() {
        #expect(!DictationMode.insertsAtCursor(frontmostBundleID: "com.TimHerglotz.VoiceKey",
                                               ownBundleID: "com.timherglotz.voicekey"))
    }

    @Test func anUnknownFrontmostAppIsStillInsertedInto() {
        // A missing bundle ID is some other process, not us.
        #expect(DictationMode.insertsAtCursor(frontmostBundleID: nil,
                                              ownBundleID: "com.timherglotz.voicekey"))
    }

    @Test func anUnknownOwnBundleIDNeverSuppressesTheInsertion() {
        #expect(DictationMode.insertsAtCursor(frontmostBundleID: "com.timherglotz.voicekey",
                                              ownBundleID: nil))
    }

    // MARK: - Bundle ID → mode mapping

    @Test func terminalsAndEditorsMapToCodeMode() {
        let codeBundleIDs = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.apple.dt.Xcode",
            "dev.zed.Zed",
            "com.sublimetext.4",
            "com.github.GitHubClient",
        ]

        for bundleID in codeBundleIDs {
            #expect(DictationMode.mode(forBundleID: bundleID) == .code, "expected .code for \(bundleID)")
        }
    }

    @Test func jetBrainsIDEsMapToCodeModeByPrefix() {
        #expect(DictationMode.mode(forBundleID: "com.jetbrains.intellij") == .code)
    }

    @Test func mailClientsMapToEmailMode() {
        let emailBundleIDs = [
            "com.apple.mail",
            "com.microsoft.Outlook",
            "com.readdle.SparkDesktop",
            "com.superhuman.electron",
        ]

        for bundleID in emailBundleIDs {
            #expect(DictationMode.mode(forBundleID: bundleID) == .email, "expected .email for \(bundleID)")
        }
    }

    @Test func unknownAppsMapToStandardMode() {
        #expect(DictationMode.mode(forBundleID: "com.apple.Safari") == .standard)
        #expect(DictationMode.mode(forBundleID: "com.tinyspeck.slackmacgap") == .standard)
    }

    @Test func missingBundleIDMapsToStandardMode() {
        #expect(DictationMode.mode(forBundleID: nil) == .standard)
    }

    @Test func bundleIDMatchingIgnoresCase() {
        #expect(DictationMode.mode(forBundleID: "COM.APPLE.TERMINAL") == .code)
        #expect(DictationMode.mode(forBundleID: "com.apple.terminal") == .code)
        #expect(DictationMode.mode(forBundleID: "COM.JetBrains.IntelliJ") == .code)
        #expect(DictationMode.mode(forBundleID: "COM.APPLE.MAIL") == .email)
    }

    @Test func jetBrainsPrefixDoesNotMatchLookalikeBundleIDs() {
        #expect(DictationMode.mode(forBundleID: "com.jetbrainsfan.notanide") == .standard)
    }

    // MARK: - Code mode formatting

    @Test func codeModeStripsSingleTrailingPeriod() {
        #expect(DictationMode.code.format("git status.") == "git status")
    }

    @Test func codeModePreservesEllipsisAndRepeatedDots() {
        #expect(DictationMode.code.format("wait...") == "wait...")
        #expect(DictationMode.code.format("wait…") == "wait…")
    }

    @Test func codeModePreservesOtherTerminalPunctuation() {
        #expect(DictationMode.code.format("really?") == "really?")
        #expect(DictationMode.code.format("stop!") == "stop!")
    }

    @Test func codeModePreservesInteriorPeriodsAndCasing() {
        #expect(DictationMode.code.format("node.js is fine.") == "node.js is fine")
        #expect(DictationMode.code.format("Make It So") == "Make It So")
    }

    @Test func codeModeTrimsTrailingWhitespaceBeforeStrippingPeriod() {
        #expect(DictationMode.code.format("git status.  ") == "git status")
        #expect(DictationMode.code.format("git status  ") == "git status")
    }

    @Test func codeModeLeavesTextWithoutTrailingPeriodAlone() {
        #expect(DictationMode.code.format("git status") == "git status")
    }

    // MARK: - Email mode formatting

    @Test func emailModeAppendsPeriodAfterLetterOrDigit() {
        #expect(DictationMode.email.format("Thanks for the update") == "Thanks for the update.")
        #expect(DictationMode.email.format("We ship on day 3") == "We ship on day 3.")
    }

    @Test func emailModeLeavesSentencePunctuationUntouched() {
        #expect(DictationMode.email.format("Thanks.") == "Thanks.")
        #expect(DictationMode.email.format("Really?") == "Really?")
        #expect(DictationMode.email.format("Wow!") == "Wow!")
        #expect(DictationMode.email.format("Here you go:") == "Here you go:")
        #expect(DictationMode.email.format("Well…") == "Well…")
    }

    @Test func emailModeTrimsTrailingWhitespaceBeforeAppending() {
        #expect(DictationMode.email.format("Thanks for the update  ") == "Thanks for the update.")
    }

    // MARK: - Standard mode formatting

    @Test func standardModeReturnsInputUnchanged() {
        #expect(DictationMode.standard.format("Hello there") == "Hello there")
        #expect(DictationMode.standard.format("Hello there.") == "Hello there.")
        #expect(DictationMode.standard.format("  spaced  ") == "  spaced  ")
    }

    // MARK: - Degenerate input

    @Test func everyModeReturnsEmptyStringForEmptyInput() {
        for mode in [DictationMode.code, .email, .standard] {
            #expect(mode.format("") == "", "expected empty output for \(mode)")
        }
    }

    @Test func everyModeHandlesWhitespaceOnlyInputWithoutAddingPunctuation() {
        for mode in [DictationMode.code, .email, .standard] {
            #expect(!mode.format("   ").contains("."), "expected no punctuation added for \(mode)")
        }
    }
}
