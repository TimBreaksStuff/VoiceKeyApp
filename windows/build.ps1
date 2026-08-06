# Publishes a self-contained VoiceKey.exe into windows/publish.
# -Run launches it afterwards. The macOS counterpart is macos/build.sh.
param([switch]$Run)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dotnet publish VoiceKey.App/VoiceKey.App.csproj `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false `
    -o publish

Write-Host "built publish/VoiceKey.exe"
if ($Run) { Start-Process publish/VoiceKey.exe }
