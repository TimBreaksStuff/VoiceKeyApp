# Publishes a self-contained VoiceKey.exe into windows/publish.
# -Run launches it afterwards. The macOS counterpart is macos/build.sh.
param([switch]$Run)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dotnet publish VoiceKey.App/VoiceKey.App.csproj `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false `
    -o publish

# $ErrorActionPreference does not apply to native commands: without this the
# script would announce a build that did not happen and -Run would launch the
# previous exe. A running VoiceKey locks publish\*.dll and fails the copy.
if ($LASTEXITCODE -ne 0) {
    Write-Host "build failed - see the dotnet output above" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "built publish/VoiceKey.exe"
if ($Run) { Start-Process publish/VoiceKey.exe }
