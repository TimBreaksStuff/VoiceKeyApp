namespace VoiceKey.Core.Tests;

public class DictationModeTests
{
    // MARK: - Dictating while VoiceKey itself is frontmost

    [Fact]
    public void ADictationIsInsertedIntoWhateverOtherAppIsFrontmost()
    {
        Assert.True(DictationModes.InsertsAtCursor("Code", "VoiceKey"));
    }

    [Fact]
    public void ADictationTakenWhileVoiceKeyIsFrontmostIsNotInserted()
    {
        Assert.False(DictationModes.InsertsAtCursor("VoiceKey", "VoiceKey"));
    }

    [Fact]
    public void TheFrontmostAppIsMatchedWithoutRegardToCase()
    {
        Assert.False(DictationModes.InsertsAtCursor("voicekey", "VoiceKey"));
    }

    [Fact]
    public void AnUnknownForegroundAppIsAssumedToBeSomewhereElse()
    {
        Assert.True(DictationModes.InsertsAtCursor(null, "VoiceKey"));
        Assert.True(DictationModes.InsertsAtCursor("Code", null));
    }

    // MARK: - Process name → mode mapping

    [Fact]
    public void TerminalsAndEditorsMapToCodeMode()
    {
        string[] codeProcesses =
        [
            "WindowsTerminal.exe",
            "cmd.exe",
            "powershell.exe",
            "pwsh.exe",
            "alacritty.exe",
            "Code.exe",
            "Cursor.exe",
            "devenv.exe",
            "Zed.exe",
            "sublime_text.exe",
            "GitHubDesktop.exe",
        ];

        foreach (var process in codeProcesses)
            Assert.Equal(DictationMode.Code, DictationModes.ForProcess(process));
    }

    [Fact]
    public void JetBrainsIdesMapToCodeMode()
    {
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("idea64.exe"));
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("pycharm64.exe"));
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("rider64.exe"));
    }

    [Fact]
    public void MailClientsMapToEmailMode()
    {
        string[] emailProcesses = ["OUTLOOK.EXE", "olk.exe", "thunderbird.exe", "HxOutlook.exe"];

        foreach (var process in emailProcesses)
            Assert.Equal(DictationMode.Email, DictationModes.ForProcess(process));
    }

    [Fact]
    public void UnknownAppsMapToStandardMode()
    {
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess("msedge.exe"));
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess("slack.exe"));
    }

    [Fact]
    public void MissingProcessNameMapsToStandardMode()
    {
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess(null));
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess(""));
    }

    [Fact]
    public void ProcessMatchingIgnoresCase()
    {
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("CODE.EXE"));
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("code.exe"));
        Assert.Equal(DictationMode.Email, DictationModes.ForProcess("Outlook.exe"));
    }

    [Fact]
    public void ProcessMatchingAcceptsNamesWithAndWithoutTheExeSuffix()
    {
        // Win32 hands back "Code" from the process table but "Code.exe" from a
        // module path; both name the same app.
        Assert.Equal(DictationMode.Code, DictationModes.ForProcess("Code"));
        Assert.Equal(DictationMode.Email, DictationModes.ForProcess("outlook"));
    }

    [Fact]
    public void ProcessMatchingIgnoresAnyLeadingPath()
    {
        Assert.Equal(DictationMode.Code,
            DictationModes.ForProcess(@"C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe"));
    }

    [Fact]
    public void LookalikeProcessNamesDoNotMatch()
    {
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess("codecs.exe"));
        Assert.Equal(DictationMode.Standard, DictationModes.ForProcess("outlookhelper.exe"));
    }

    // MARK: - Code mode formatting

    [Fact]
    public void CodeModeStripsSingleTrailingPeriod()
    {
        Assert.Equal("git status", DictationMode.Code.Format("git status."));
    }

    [Fact]
    public void CodeModePreservesEllipsisAndRepeatedDots()
    {
        Assert.Equal("wait...", DictationMode.Code.Format("wait..."));
        Assert.Equal("wait…", DictationMode.Code.Format("wait…"));
    }

    [Fact]
    public void CodeModePreservesOtherTerminalPunctuation()
    {
        Assert.Equal("really?", DictationMode.Code.Format("really?"));
        Assert.Equal("stop!", DictationMode.Code.Format("stop!"));
    }

    [Fact]
    public void CodeModePreservesInteriorPeriodsAndCasing()
    {
        Assert.Equal("node.js is fine", DictationMode.Code.Format("node.js is fine."));
        Assert.Equal("Make It So", DictationMode.Code.Format("Make It So"));
    }

    [Fact]
    public void CodeModeTrimsTrailingWhitespaceBeforeStrippingPeriod()
    {
        Assert.Equal("git status", DictationMode.Code.Format("git status.  "));
        Assert.Equal("git status", DictationMode.Code.Format("git status  "));
    }

    [Fact]
    public void CodeModeLeavesTextWithoutTrailingPeriodAlone()
    {
        Assert.Equal("git status", DictationMode.Code.Format("git status"));
    }

    // MARK: - Email mode formatting

    [Fact]
    public void EmailModeAppendsPeriodAfterLetterOrDigit()
    {
        Assert.Equal("Thanks for the update.", DictationMode.Email.Format("Thanks for the update"));
        Assert.Equal("We ship on day 3.", DictationMode.Email.Format("We ship on day 3"));
    }

    [Fact]
    public void EmailModeLeavesSentencePunctuationUntouched()
    {
        Assert.Equal("Thanks.", DictationMode.Email.Format("Thanks."));
        Assert.Equal("Really?", DictationMode.Email.Format("Really?"));
        Assert.Equal("Wow!", DictationMode.Email.Format("Wow!"));
        Assert.Equal("Here you go:", DictationMode.Email.Format("Here you go:"));
        Assert.Equal("Well…", DictationMode.Email.Format("Well…"));
    }

    [Fact]
    public void EmailModeTrimsTrailingWhitespaceBeforeAppending()
    {
        Assert.Equal("Thanks for the update.", DictationMode.Email.Format("Thanks for the update  "));
    }

    // MARK: - Standard mode formatting

    [Fact]
    public void StandardModeReturnsInputUnchanged()
    {
        Assert.Equal("Hello there", DictationMode.Standard.Format("Hello there"));
        Assert.Equal("Hello there.", DictationMode.Standard.Format("Hello there."));
        Assert.Equal("  spaced  ", DictationMode.Standard.Format("  spaced  "));
    }

    // MARK: - Degenerate input

    [Fact]
    public void EveryModeReturnsEmptyStringForEmptyInput()
    {
        foreach (var mode in AllModes) Assert.Equal("", mode.Format(""));
    }

    [Fact]
    public void EveryModeHandlesWhitespaceOnlyInputWithoutAddingPunctuation()
    {
        foreach (var mode in AllModes) Assert.DoesNotContain(".", mode.Format("   "));
    }

    private static readonly DictationMode[] AllModes =
        [DictationMode.Code, DictationMode.Email, DictationMode.Standard];
}
