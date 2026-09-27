# Builds the Windows release and packages it with Inno Setup.
# Usage (from client/):  powershell -ExecutionPolicy Bypass -File tool\build.ps1
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Version -eq "") {
    $pubspec = Get-Content (Join-Path $root "pubspec.yaml") -Raw
    if ($pubspec -match '(?m)^version:\s*(\S+)') {
        $Version = $Matches[1].Split('+')[0]
    } else {
        $Version = "0.0.0"
    }
}
Write-Host "Building ZionMusicalCentre $Version"

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dart run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Warning "Inno Setup 6 not found - skipping installer. Binary is in build\windows\x64\runner\Release"
    exit 0
}

& $iscc "/DMyAppVersion=$Version" (Join-Path $root "tool\installer.iss")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done: dist\ZionMusicalCentreSetup-$Version.exe"
