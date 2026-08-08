import Testing
@testable import VoiceKeyCore

@Suite struct AppUpdateTests {

    // MARK: - Which release is newer

    @Test func aReleaseIsNewerOnlyWhenItsNumbersAreHigher() {
        #expect(AppUpdate.isNewer("1.3.0", than: "1.2.0"))
        #expect(AppUpdate.isNewer("1.2.1", than: "1.2.0"))
        #expect(AppUpdate.isNewer("2.0.0", than: "1.9.9"))
        #expect(!AppUpdate.isNewer("1.2.0", than: "1.2.0"))
        #expect(!AppUpdate.isNewer("1.1.0", than: "1.2.0"))
    }

    @Test func theTagsLeadingVeeIsNotPartOfTheNumber() {
        #expect(AppUpdate.isNewer("v1.3.0", than: "1.2.0"))
        #expect(!AppUpdate.isNewer("v1.2.0", than: "1.2.0"))
    }

    @Test func missingComponentsCountAsZeroRatherThanAsNewer() {
        #expect(AppUpdate.isNewer("1.3", than: "1.2.9"))
        #expect(!AppUpdate.isNewer("1.2", than: "1.2.0"))
        #expect(AppUpdate.isNewer("1.2.0.1", than: "1.2.0"))
    }

    /// A tag we cannot read is not an update. Offering to install something whose
    /// version is unknown is worse than saying nothing.
    @Test func aVersionThatDoesNotParseIsNeverNewer() {
        #expect(!AppUpdate.isNewer("nightly", than: "1.2.0"))
        #expect(!AppUpdate.isNewer("", than: "1.2.0"))
        #expect(!AppUpdate.isNewer("1.2.0-beta", than: "1.2.0"))
    }

    @Test func theVersionOfferedToTheUserIsTheTagWithoutItsVee() {
        #expect(AppUpdate.number("v1.3.0") == "1.3.0")
        #expect(AppUpdate.number("1.3.0") == "1.3.0")
    }

    // MARK: - Which file to download

    @Test func picksThisPlatformsZipAndLeavesTheOthersAlone() {
        let assets = [ReleaseAsset(name: "VoiceKey-1.3.0-macos-arm64.zip", url: "https://example.test/mac"),
                      ReleaseAsset(name: "VoiceKey-1.3.0-win-x64.zip", url: "https://example.test/win")]

        #expect(AppUpdate.asset(assets, platform: "macos-arm64")?.url == "https://example.test/mac")
        #expect(AppUpdate.asset(assets, platform: "win-x64")?.url == "https://example.test/win")
    }

    @Test func releaseWithNothingForThisPlatformOffersNothing() {
        let assets = [ReleaseAsset(name: "VoiceKey-1.3.0-win-x64.zip", url: "https://example.test/win")]

        #expect(AppUpdate.asset(assets, platform: "macos-arm64") == nil)
    }

    @Test func onlyZipsCount() {
        let assets = [ReleaseAsset(name: "VoiceKey-1.3.0-macos-arm64.zip.sha256", url: "https://example.test/sum"),
                      ReleaseAsset(name: "VoiceKey-1.3.0-macos-arm64.zip", url: "https://example.test/mac")]

        #expect(AppUpdate.asset(assets, platform: "macos-arm64")?.url == "https://example.test/mac")
    }

    // MARK: - What the footer row says

    @Test func theFooterRowOnlyAppearsOnceThereIsSomethingToSay() {
        #expect(!AppUpdate.isVisible(.idle))
        #expect(!AppUpdate.isVisible(.upToDate))
        #expect(AppUpdate.isVisible(.checking))
        #expect(AppUpdate.isVisible(.available(version: "1.3.0", url: "https://example.test/mac")))
        #expect(AppUpdate.isVisible(.failed("no network")))
    }

    @Test func theRowNamesTheVersionItWouldInstall() {
        #expect(AppUpdate.label(.available(version: "1.3.0", url: "https://example.test/mac"))
                == "Update to 1.3.0")
    }

    @Test func progressIsReportedAsItGoes() {
        #expect(AppUpdate.label(.checking) == "Checking for updates…")
        #expect(AppUpdate.label(.downloading(percent: 42)) == "Downloading… 42%")
        #expect(AppUpdate.label(.installing) == "Installing…")
    }

    @Test func upToDateAndIdleStillHaveWordsForTheSettingsRow() {
        #expect(AppUpdate.label(.idle) == "Check for updates")
        #expect(AppUpdate.label(.upToDate) == "VoiceKey is up to date")
    }

    /// The reason belongs on the row: "failed" alone gives nothing to act on.
    @Test func aFailureSaysWhatWentWrong() {
        #expect(AppUpdate.label(.failed("no network")) == "Update check failed — no network")
    }

    // MARK: - What a click on the row does

    @Test func clickingAsksForACheckUntilThereIsSomethingToInstall() {
        #expect(AppUpdate.click(.idle) == .check)
        #expect(AppUpdate.click(.upToDate) == .check)
        #expect(AppUpdate.click(.failed("no network")) == .check)
        #expect(AppUpdate.click(.available(version: "1.3.0", url: "https://example.test/mac")) == .install)
    }

    /// A click while work is in flight must not start the same work twice.
    @Test func clickingWhileBusyDoesNothing() {
        #expect(AppUpdate.click(.checking) == .none)
        #expect(AppUpdate.click(.downloading(percent: 42)) == .none)
        #expect(AppUpdate.click(.installing) == .none)
    }
}
