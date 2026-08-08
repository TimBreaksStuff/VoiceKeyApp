# Runs the VoiceKey.Core suite. The macOS counterpart is macos/test.sh.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dotnet test VoiceKey.Core.Tests/VoiceKey.Core.Tests.csproj @args

# A failing suite already exits non-zero, but only because dotnet test is the
# last native command - another one below would overwrite $LASTEXITCODE, and
# $ErrorActionPreference does not cover native commands. Say it outright.
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
