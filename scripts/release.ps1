<#
.SYNOPSIS
    Builds a signed release APK and publishes it as a GitHub Release.

.DESCRIPTION
    1. Checks that you are on an up-to-date, clean main branch.
    2. Checks the signing key, the Firebase config and the GitHub CLI.
    3. Runs the tests and builds the release APK.
    4. Confirms the APK is signed with your upload key, not the debug key.
    5. Creates the tag (for example v1.0.0) and the GitHub Release with the APK attached.

    The tag also marks the exact firmware and model files in the repository.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -Version 1.0.0

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -Version 1.0.0 -Draft
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [int]$BuildNumber = 0,
    [switch]$Draft,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

function Write-Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "    $text" -ForegroundColor Green }
function Fail($text)       { Write-Host "`nERROR: $text" -ForegroundColor Red; exit 1 }

# Runs a program and returns its output, without PowerShell treating
# normal messages on stderr as errors.
function Run-Quiet {
    param([string]$Exe, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } }
    finally { $ErrorActionPreference = $old }
    return ,@($out)
}

$repo = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repo "app"
$tag = "v$Version"
Set-Location $repo

# ---------------------------------------------------------------------------
Write-Step "Checking tools"
# ---------------------------------------------------------------------------
foreach ($tool in @("git", "flutter", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        if ($tool -eq "gh") { Fail "GitHub CLI is missing. Install it with: winget install --id GitHub.cli   then run: gh auth login" }
        Fail "$tool is not on PATH."
    }
}
Run-Quiet "gh" @("auth", "status") | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "GitHub CLI is not signed in. Run: gh auth login" }
Write-Ok "git, flutter and gh are ready."

# ---------------------------------------------------------------------------
Write-Step "Checking the Git branch"
# ---------------------------------------------------------------------------
$branch = (Run-Quiet "git" @("rev-parse", "--abbrev-ref", "HEAD"))[0].Trim()
if ($branch -ne "main") { Fail "You are on '$branch'. Switch to main first: git checkout main" }

$dirty = Run-Quiet "git" @("status", "--porcelain")
if (($dirty | Where-Object { $_.Trim() }).Count -gt 0) {
    Fail "You have uncommitted changes. Commit them through a pull request first, or run: git stash"
}

Run-Quiet "git" @("fetch", "origin", "main", "--tags") | Out-Null
$local  = (Run-Quiet "git" @("rev-parse", "HEAD"))[0].Trim()
$remote = (Run-Quiet "git" @("rev-parse", "origin/main"))[0].Trim()
if ($local -ne $remote) { Fail "Your main is not the same as GitHub. Run: git pull" }

Run-Quiet "git" @("rev-parse", "-q", "--verify", "refs/tags/$tag") | Out-Null
if ($LASTEXITCODE -eq 0) { Fail "Tag $tag already exists. Choose a new version number." }
Write-Ok "On main, clean and up to date. Tag $tag is free."

if ($BuildNumber -le 0) {
    $BuildNumber = [int]((Run-Quiet "git" @("rev-list", "--count", "HEAD"))[0].Trim())
}
Write-Ok "Version $Version, build number $BuildNumber."

# ---------------------------------------------------------------------------
Write-Step "Checking signing key and Firebase config"
# ---------------------------------------------------------------------------
$propsFile = Join-Path $appDir "android\key.properties"
if (-not (Test-Path $propsFile)) { Fail "app\android\key.properties is missing. Run scripts\setup_signing.ps1 first." }
$props = @{}
foreach ($line in Get-Content $propsFile) {
    if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$Matches[1]] = $Matches[2] }
}
$keyFile = $props["storeFile"] -replace '/', '\'
if (-not $keyFile -or -not (Test-Path $keyFile)) { Fail "The key file in key.properties was not found: $keyFile" }
if (-not (Select-String -Path (Join-Path $appDir "android\app\build.gradle") -Pattern "signingConfigs.release" -Quiet)) {
    Fail "build.gradle does not use the release key yet. Run scripts\setup_signing.ps1 and merge that change first."
}
if (-not (Test-Path (Join-Path $appDir "android\app\google-services.json"))) {
    Fail "app\android\app\google-services.json is missing. Download it from the Firebase console."
}
Write-Ok "Signing key and Firebase config found."

# ---------------------------------------------------------------------------
Write-Step "Building the app"
# ---------------------------------------------------------------------------
Set-Location $appDir
& flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed." }

if (-not $SkipTests) {
    & flutter test
    if ($LASTEXITCODE -ne 0) { Fail "Some tests failed. Fix them, or run again with -SkipTests." }
}

& flutter build apk --release --build-name $Version --build-number $BuildNumber
if ($LASTEXITCODE -ne 0) { Fail "flutter build apk failed." }
Set-Location $repo

$builtApk = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $builtApk)) { Fail "The APK was not found at $builtApk" }

$outDir = Join-Path $appDir "build\release"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$apkName = "assistive-navigation-$tag.apk"
$apk = Join-Path $outDir $apkName
Copy-Item $builtApk $apk -Force
$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
Write-Ok "Built $apkName ($sizeMb MB)."

# ---------------------------------------------------------------------------
Write-Step "Checking the APK signature"
# ---------------------------------------------------------------------------
# apksigner (from the Android SDK build-tools) reads modern APK signatures.
$apksigner = $null
$sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") | Where-Object { $_ }
foreach ($root in $sdkRoots) {
    $bt = Join-Path $root "build-tools"
    if (-not $apksigner -and (Test-Path $bt)) {
        $found = Get-ChildItem $bt -Directory | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "apksigner.bat" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) { $apksigner = $found }
    }
}
if ($apksigner) {
    $cert = (Run-Quiet $apksigner @("verify", "--print-certs", $apk)) -join "`n"
    if ($LASTEXITCODE -ne 0) { Fail "The APK signature is not valid:`n$cert" }
    if ($cert -match "Android Debug") { Fail "The APK is signed with the DEBUG key. Check key.properties and build.gradle." }
    $dn = ($cert -split "`n" | Where-Object { $_ -match "certificate DN" } | Select-Object -First 1)
    Write-Ok "Signed with your upload key. $dn"
} else {
    Write-Host "    apksigner not found, so the signature was not checked." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Write-Step "Preparing release notes"
# ---------------------------------------------------------------------------
$notes = @"
Prototype release of the CNN-based smart assistive navigation and caregiver alert system.

## What it does
- Classifies what is in front of the user with an on-device CNN (MobileNetV3-Small, TensorFlow Lite). Classification works offline.
- Reads distance from the ESP32 + HC-SR04 wearable over Bluetooth Low Energy and grades the risk.
- Speaks warnings aloud and stays silent when the path is clear.
- Sends an SOS alert with GPS location to a paired caregiver after a 5-second countdown that can be cancelled.

## Requirements
- Android 8.0 (API 26) or newer. Tested on a Samsung Galaxy S22 Ultra (Android 16).
- The ESP32 distance sensor unit, flashed from the firmware folder at tag $tag.
- Internet connection for sign-in and SOS alerts.

## Install
1. Download **$apkName** below on the phone.
2. Open it and allow "Install unknown apps" when asked.
3. Allow camera, location and Bluetooth permissions when the app asks.

## File check
SHA-256: ``$sha``

This is a controlled prototype release for academic evaluation, not a public app store release.
"@
$notesFile = Join-Path $outDir "release-notes-$tag.md"
[System.IO.File]::WriteAllText($notesFile, $notes, (New-Object System.Text.UTF8Encoding $false))
Write-Ok "Notes saved to $notesFile"

Write-Host ""
Write-Host "Ready to publish:" -ForegroundColor Yellow
Write-Host "    Tag:     $tag (on main, commit $($local.Substring(0,7)))"
Write-Host "    File:    $apkName ($sizeMb MB)"
if ($Draft) { Write-Host "    Type:    draft (only you can see it until you publish it on GitHub)" }
$answer = Read-Host "Publish this release to GitHub now? (y/n)"
if ($answer -ne "y") {
    Write-Host "Stopped. Nothing was published. The APK is at $apk"
    exit 0
}

# ---------------------------------------------------------------------------
Write-Step "Publishing the GitHub Release"
# ---------------------------------------------------------------------------
$ghArgs = @("release", "create", $tag, $apk,
            "--target", "main",
            "--title", "$tag - Prototype release",
            "--notes-file", $notesFile)
if ($Draft) { $ghArgs += "--draft" }
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { Fail "gh release create failed." }

$url = (Run-Quiet "gh" @("release", "view", $tag, "--json", "url", "--jq", ".url"))[0].Trim()
Write-Host "`nDone. Release page: $url" -ForegroundColor Green
Write-Host "Test it on a phone: download the APK, install it, sign in, start detection, hear a warning, send SOS, check the caregiver phone."
