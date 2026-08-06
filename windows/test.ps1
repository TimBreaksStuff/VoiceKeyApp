# Runs the VoiceKey.Core suite. The macOS counterpart is macos/test.sh.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dotnet test VoiceKey.Core.Tests/VoiceKey.Core.Tests.csproj @args
