namespace VoiceKey.Core.Tests;

public class LaunchAtLoginTests
{
    // MARK: - The row's text

    [Fact]
    public void RowCarriesTheStateAfterThePlatformsOwnWording()
    {
        Assert.Equal("Start with Windows — On",
            LaunchAtLogin.Label("Start with Windows", LaunchAtLoginState.On));
        Assert.Equal("Start with Windows — Off",
            LaunchAtLogin.Label("Start with Windows", LaunchAtLoginState.Off));
    }

    [Fact]
    public void RegisteredButVetoedBySettingsReadsAsBlockedRatherThanOn()
    {
        Assert.Equal("Start with Windows — Blocked",
            LaunchAtLogin.Label("Start with Windows", LaunchAtLoginState.Blocked));
    }

    // MARK: - What a click asks for

    [Fact]
    public void ClickingTogglesWhateverTheSystemReports()
    {
        Assert.Equal(LaunchAtLoginAction.Disable, LaunchAtLogin.Click(LaunchAtLoginState.On));
        Assert.Equal(LaunchAtLoginAction.Enable, LaunchAtLogin.Click(LaunchAtLoginState.Off));
    }

    [Fact]
    public void ClickingWhileBlockedOpensTheSystemsListInsteadOfRegisteringAgain()
    {
        Assert.Equal(LaunchAtLoginAction.OpenSettings,
            LaunchAtLogin.Click(LaunchAtLoginState.Blocked));
    }
}
