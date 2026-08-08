import Testing
@testable import VoiceKeyCore

@Suite struct LaunchAtLoginTests {

    // MARK: - The row's text

    @Test func rowCarriesTheStateAfterThePlatformsOwnWording() {
        #expect(LaunchAtLogin.label("Open at login", .on) == "Open at login — On")
        #expect(LaunchAtLogin.label("Open at login", .off) == "Open at login — Off")
    }

    @Test func registeredButVetoedBySettingsReadsAsBlockedRatherThanOn() {
        #expect(LaunchAtLogin.label("Open at login", .blocked) == "Open at login — Blocked")
    }

    // MARK: - What a click asks for

    @Test func clickingTogglesWhateverTheSystemReports() {
        #expect(LaunchAtLogin.click(.on) == .disable)
        #expect(LaunchAtLogin.click(.off) == .enable)
    }

    @Test func clickingWhileBlockedOpensTheSystemsListInsteadOfRegisteringAgain() {
        #expect(LaunchAtLogin.click(.blocked) == .openSettings)
    }
}
