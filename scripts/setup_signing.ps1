<#
.SYNOPSIS
    One-time setup: creates the release signing key and connects it to the Android build.

.DESCRIPTION
    1. Creates an upload key (.jks) in your user folder, outside the repository.
    2. Writes app/android/key.properties with the key details.
    3. Updates app/android/app/build.gradle so release builds use this key.

    key.properties and *.jks are already in .gitignore, so they are never committed.
    Only the build.gradle change needs to be committed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup_signing.ps1
#>

param(
    [string]$KeyPath = (Join-Path $env:USERPROFILE "assistive-nav-upload-key.jks"),
    [string]$Alias = "upload",
    [string]$DName = "CN=Benedict Muuo, OU=School of Computing and Engineering Sciences, O=Strathmore University, L=Nairobi, C=KE"
)

$ErrorActionPreference = "Stop"

function Write-Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "    $text" -ForegroundColor Green }
function Fail($text)       { Write-Host "`nERROR: $text" -ForegroundColor Red; exit 1 }

function Write-Utf8NoBom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

$repo = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repo "app\android"
$gradleFile = Join-Path $androidDir "app\build.gradle"
$propsFile  = Join-Path $androidDir "key.properties"

if (-not (Test-Path $gradleFile)) { Fail "Cannot find $gradleFile. Run this script from inside the repository." }

# ---------------------------------------------------------------------------
Write-Step "Finding keytool"
# ---------------------------------------------------------------------------
$keytool = $null
$cmd = Get-Command keytool -ErrorAction SilentlyContinue
if ($cmd) { $keytool = $cmd.Source }
if (-not $keytool) {
    $candidates = @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe",
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe"
    )
    if ($env:JAVA_HOME) { $candidates = @("$env:JAVA_HOME\bin\keytool.exe") + $candidates }
    foreach ($c in $candidates) { if (Test-Path $c) { $keytool = $c; break } }
}
if (-not $keytool) {
    Fail "keytool was not found. Run 'flutter doctor -v', look for 'Java binary at:', and run this script again with that folder added to PATH."
}
Write-Ok "Using $keytool"

# ---------------------------------------------------------------------------
Write-Step "Signing key"
# ---------------------------------------------------------------------------
$secure = Read-Host "Choose a password for the key (at least 6 characters)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if ($password.Length -lt 6) { Fail "The password must be at least 6 characters." }
if ($password -match '[\\:=#!\s]') { Fail "Use only letters, numbers and symbols like @ or - in the password (no spaces, \ : = # or !)." }

if (Test-Path $KeyPath) {
    Write-Ok "Key already exists at $KeyPath. Using it (the password must be the one you chose before)."
} else {
    & $keytool -genkeypair -v -keystore $KeyPath -storetype PKCS12 -keyalg RSA -keysize 2048 `
        -validity 10000 -alias $Alias -dname $DName -storepass $password -keypass $password
    if ($LASTEXITCODE -ne 0) { Fail "keytool could not create the key." }
    Write-Ok "Created $KeyPath"
}

# Check that the password opens the key.
& $keytool -list -keystore $KeyPath -storepass $password -alias $Alias | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "The password does not open $KeyPath." }

# ---------------------------------------------------------------------------
Write-Step "Writing app\android\key.properties"
# ---------------------------------------------------------------------------
$storeFile = $KeyPath -replace '\\', '/'
$props = @"
storePassword=$password
keyPassword=$password
keyAlias=$Alias
storeFile=$storeFile
"@
Write-Utf8NoBom $propsFile ($props + "`n")
Write-Ok "Done (this file is ignored by Git)."

# ---------------------------------------------------------------------------
Write-Step "Updating app\android\app\build.gradle"
# ---------------------------------------------------------------------------
$gradle = [System.IO.File]::ReadAllText($gradleFile)
$nl = "`n"
if ($gradle.Contains("`r`n")) { $nl = "`r`n" }

if ($gradle.Contains("keystoreProperties")) {
    Write-Ok "Already updated. Nothing to change."
} else {
    $loader = @(
        'def keystoreProperties = new Properties()',
        'def keystorePropertiesFile = rootProject.file("key.properties")',
        'if (keystorePropertiesFile.exists()) {',
        '    keystorePropertiesFile.withReader("UTF-8") { reader -> keystoreProperties.load(reader) }',
        '}',
        '',
        'android {'
    ) -join $nl

    $signing = @(
        '    signingConfigs {',
        '        release {',
        '            if (keystorePropertiesFile.exists()) {',
        '                keyAlias = keystoreProperties["keyAlias"]',
        '                keyPassword = keystoreProperties["keyPassword"]',
        '                storeFile = file(keystoreProperties["storeFile"])',
        '                storePassword = keystoreProperties["storePassword"]',
        '            }',
        '        }',
        '    }',
        '',
        '    buildTypes {'
    ) -join $nl

    $releaseLine = @(
        '            // Uses the upload key when key.properties exists, otherwise the debug key.',
        '            signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug'
    ) -join $nl

    $oldRelease = [regex]'(?m)^[ \t]*// TODO: Add your own signing config for the release build\.\r?\n[ \t]*// Signing with the debug keys for now, so `flutter run --release` works\.\r?\n[ \t]*signingConfig = signingConfigs\.debug'
    $simpleRelease = [regex]'(?m)^[ \t]*signingConfig = signingConfigs\.debug'

    if (([regex]'(?m)^android \{').Matches($gradle).Count -ne 1) { Fail "Could not find 'android {' in build.gradle." }
    if (([regex]'(?m)^    buildTypes \{').Matches($gradle).Count -ne 1) { Fail "Could not find 'buildTypes {' in build.gradle." }

    $gradle = ([regex]'(?m)^android \{').Replace($gradle, $loader, 1)
    $gradle = ([regex]'(?m)^    buildTypes \{').Replace($gradle, $signing, 1)
    if ($oldRelease.IsMatch($gradle)) {
        $gradle = $oldRelease.Replace($gradle, $releaseLine, 1)
    } elseif ($simpleRelease.IsMatch($gradle)) {
        $gradle = $simpleRelease.Replace($gradle, $releaseLine, 1)
    } else {
        Fail "Could not find 'signingConfig = signingConfigs.debug' in build.gradle."
    }

    Write-Utf8NoBom $gradleFile $gradle
    Write-Ok "Release builds will now be signed with your upload key."
}

# ---------------------------------------------------------------------------
Write-Host "`nSetup finished." -ForegroundColor Green
Write-Host "IMPORTANT: back up $KeyPath and its password (for example on Google Drive)."
Write-Host "If you lose them, phones with the old app cannot update to a new version."
Write-Host "`nNext: commit the build.gradle change through a pull request, then run scripts\release.ps1."
