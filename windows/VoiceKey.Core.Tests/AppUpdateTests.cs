namespace VoiceKey.Core.Tests;

public class AppUpdateTests
{
    // MARK: - Which release is newer

    [Fact]
    public void AReleaseIsNewerOnlyWhenItsNumbersAreHigher()
    {
        Assert.True(AppUpdate.IsNewer("1.3.0", "1.2.0"));
        Assert.True(AppUpdate.IsNewer("1.2.1", "1.2.0"));
        Assert.True(AppUpdate.IsNewer("2.0.0", "1.9.9"));
        Assert.False(AppUpdate.IsNewer("1.2.0", "1.2.0"));
        Assert.False(AppUpdate.IsNewer("1.1.0", "1.2.0"));
    }

    [Fact]
    public void TheTagsLeadingVeeIsNotPartOfTheNumber()
    {
        Assert.True(AppUpdate.IsNewer("v1.3.0", "1.2.0"));
        Assert.False(AppUpdate.IsNewer("v1.2.0", "1.2.0"));
    }

    [Fact]
    public void MissingComponentsCountAsZeroRatherThanAsNewer()
    {
        Assert.True(AppUpdate.IsNewer("1.3", "1.2.9"));
        Assert.False(AppUpdate.IsNewer("1.2", "1.2.0"));
        Assert.True(AppUpdate.IsNewer("1.2.0.1", "1.2.0"));
    }

    /// <summary>
    /// A tag we cannot read is not an update. Offering to install something whose
    /// version is unknown is worse than saying nothing.
    /// </summary>
    [Fact]
    public void AVersionThatDoesNotParseIsNeverNewer()
    {
        Assert.False(AppUpdate.IsNewer("nightly", "1.2.0"));
        Assert.False(AppUpdate.IsNewer("", "1.2.0"));
        Assert.False(AppUpdate.IsNewer("1.2.0-beta", "1.2.0"));
    }

    [Fact]
    public void TheVersionOfferedToTheUserIsTheTagWithoutItsVee()
    {
        Assert.Equal("1.3.0", AppUpdate.Number("v1.3.0"));
        Assert.Equal("1.3.0", AppUpdate.Number("1.3.0"));
    }

    // MARK: - Which file to download

    [Fact]
    public void PicksTheWindowsZipAndLeavesTheOtherPlatformsAlone()
    {
        var assets = new List<ReleaseAsset>
        {
            new("VoiceKey-1.3.0-macos-arm64.zip", "https://example.test/mac"),
            new("VoiceKey-1.3.0-win-x64.zip", "https://example.test/win"),
        };

        Assert.Equal("https://example.test/win", AppUpdate.Asset(assets, "win-x64")?.Url);
        Assert.Equal("https://example.test/mac", AppUpdate.Asset(assets, "macos-arm64")?.Url);
    }

    [Fact]
    public void ReleaseWithNothingForThisPlatformOffersNothing()
    {
        var assets = new List<ReleaseAsset> { new("VoiceKey-1.3.0-macos-arm64.zip", "https://example.test/mac") };

        Assert.Null(AppUpdate.Asset(assets, "win-x64"));
    }

    [Fact]
    public void OnlyZipsCount()
    {
        var assets = new List<ReleaseAsset>
        {
            new("VoiceKey-1.3.0-win-x64.zip.sha256", "https://example.test/sum"),
            new("VoiceKey-1.3.0-win-x64.zip", "https://example.test/win"),
        };

        Assert.Equal("https://example.test/win", AppUpdate.Asset(assets, "win-x64")?.Url);
    }

    // MARK: - What the unpacked zip looks like

    [Fact]
    public void AZipWrappedInOneFolderIsUnwrappedToThatFolder()
    {
        Assert.Equal("VoiceKey-1.3.0-win-x64", AppUpdate.RootFolder(
            ["VoiceKey-1.3.0-win-x64/VoiceKey.exe", "VoiceKey-1.3.0-win-x64/VoiceKey.dll"]));
    }

    [Fact]
    public void AZipOfLooseFilesHasNoFolderToUnwrap()
    {
        Assert.Null(AppUpdate.RootFolder(["VoiceKey.exe", "VoiceKey.dll"]));
        Assert.Null(AppUpdate.RootFolder(["VoiceKey.exe", "runtimes/win-x64/whisper.dll"]));
        Assert.Null(AppUpdate.RootFolder([]));
    }

    [Fact]
    public void TwoTopLevelFoldersAreNotAWrapperEither()
    {
        Assert.Null(AppUpdate.RootFolder(["one/VoiceKey.exe", "two/VoiceKey.dll"]));
    }

    // MARK: - What the footer row says

    [Fact]
    public void TheFooterRowOnlyAppearsOnceThereIsSomethingToSay()
    {
        Assert.False(AppUpdate.IsVisible(UpdateStatus.Idle));
        Assert.False(AppUpdate.IsVisible(UpdateStatus.UpToDate));
        Assert.True(AppUpdate.IsVisible(UpdateStatus.Checking));
        Assert.True(AppUpdate.IsVisible(UpdateStatus.Available("1.3.0", "https://example.test/win")));
        Assert.True(AppUpdate.IsVisible(UpdateStatus.Failed("no network")));
    }

    [Fact]
    public void TheRowNamesTheVersionItWouldInstall()
    {
        Assert.Equal("Update to 1.3.0",
            AppUpdate.Label(UpdateStatus.Available("1.3.0", "https://example.test/win")));
    }

    [Fact]
    public void ProgressIsReportedAsItGoes()
    {
        Assert.Equal("Checking for updates…", AppUpdate.Label(UpdateStatus.Checking));
        Assert.Equal("Downloading… 42%", AppUpdate.Label(UpdateStatus.Downloading(42)));
        Assert.Equal("Installing…", AppUpdate.Label(UpdateStatus.Installing));
    }

    [Fact]
    public void UpToDateAndIdleStillHaveWordsForTheSettingsRow()
    {
        Assert.Equal("Check for updates", AppUpdate.Label(UpdateStatus.Idle));
        Assert.Equal("VoiceKey is up to date", AppUpdate.Label(UpdateStatus.UpToDate));
    }

    /// <summary>The reason belongs on the row: "failed" alone gives nothing to act on.</summary>
    [Fact]
    public void AFailureSaysWhatWentWrong()
    {
        Assert.Equal("Update check failed — no network",
            AppUpdate.Label(UpdateStatus.Failed("no network")));
    }

    // MARK: - What a click on the row does

    [Fact]
    public void ClickingAsksForACheckUntilThereIsSomethingToInstall()
    {
        Assert.Equal(UpdateAction.Check, AppUpdate.Click(UpdateStatus.Idle));
        Assert.Equal(UpdateAction.Check, AppUpdate.Click(UpdateStatus.UpToDate));
        Assert.Equal(UpdateAction.Check, AppUpdate.Click(UpdateStatus.Failed("no network")));
        Assert.Equal(UpdateAction.Install,
            AppUpdate.Click(UpdateStatus.Available("1.3.0", "https://example.test/win")));
    }

    /// <summary>A click while work is in flight must not start the same work twice.</summary>
    [Fact]
    public void ClickingWhileBusyDoesNothing()
    {
        Assert.Equal(UpdateAction.None, AppUpdate.Click(UpdateStatus.Checking));
        Assert.Equal(UpdateAction.None, AppUpdate.Click(UpdateStatus.Downloading(42)));
        Assert.Equal(UpdateAction.None, AppUpdate.Click(UpdateStatus.Installing));
    }
}
