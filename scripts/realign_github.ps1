# realign_github.ps1
#
# Renames the milestones and issues already on GitHub so they match the
# project's naming convention:
#   - milestones named "Phase N: Name" rather than "M1 - Name"
#   - issue titles as short imperative phrases
#
# Also adds one issue covering the repository setup itself, so the first
# branch has a number to reference like every other branch.
#
# Run once, from inside the repository:
#     .\scripts\realign_github.ps1
#
# Safe to run twice - anything already correct is left alone.

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    foreach ($dir in @("C:\Program Files\GitHub CLI",
                       "C:\Program Files (x86)\GitHub CLI",
                       "$env:LOCALAPPDATA\Programs\GitHub CLI")) {
        if (Test-Path (Join-Path $dir "gh.exe")) { $env:Path += ";$dir"; break }
    }
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: gh not found. Run: winget install --id GitHub.cli" -ForegroundColor Red
    exit 1
}

# --- milestones -------------------------------------------------------

Write-Host ""
Write-Host "==> Renaming milestones"

$milestoneNames = @{
    "M1 - CNN model"           = "Phase 1: Model and Dataset"
    "M2 - App shell"           = "Phase 2: Application Shell"
    "M3 - On-device detection" = "Phase 3: On-Device Detection"
    "M4 - Alerts and risk"     = "Phase 4: Alerts and Risk Logic"
    "M5 - Testing"             = "Phase 5: Testing and Evaluation"
    "M6 - Final build"         = "Phase 6: Final Build and Documentation"
}

$existing = gh api "repos/{owner}/{repo}/milestones?state=all" | ConvertFrom-Json

foreach ($m in $existing) {
    if ($milestoneNames.ContainsKey($m.title)) {
        $new = $milestoneNames[$m.title]
        gh api -X PATCH "repos/{owner}/{repo}/milestones/$($m.number)" `
            -f title="$new" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    $($m.title)  ->  $new" -ForegroundColor Green
        } else {
            Write-Host "    FAILED  $($m.title)" -ForegroundColor Red
        }
    }
    elseif ($m.title -like "Phase *") {
        Write-Host "    already correct: $($m.title)" -ForegroundColor DarkGray
    }
}

# --- issue titles -----------------------------------------------------

Write-Host ""
Write-Host "==> Shortening issue titles"

$issueTitles = @{
    "Build the training dataset from public sources"             = "Build the training dataset"
    "Train and evaluate the CNN classifier"                      = "Train and evaluate the CNN"
    "Export the model to TFLite for the phone"                   = "Export the model to TFLite"
    "Collect local images around Strathmore"                     = "Collect local images at Strathmore"
    "Retrain with local images and compare results"              = "Retrain with local images"
    "Set up the Flutter project and Firebase"                    = "Set up Flutter and Firebase"
    "Build authentication and caregiver pairing"                 = "Build authentication and pairing"
    "Make every screen work with a screen reader"                = "Add screen reader support"
    "Run the TFLite model on camera frames"                      = "Run the model on camera frames"
    "Send an SOS alert with location to the caregiver"           = "Send SOS alert with location"
    "Add the DistanceSource interface with a mock implementation" = "Add DistanceSource interface"
    "Build the ESP32 sensor unit and BLE link"                   = "Build the ESP32 sensor unit"
    "Run scenario trials in real environments"                   = "Run scenario trials"
    "Measure latency, battery and SOS delivery"                  = "Measure latency and battery"
    "Produce the release build and demo video"                   = "Build the release and demo video"
}

$issues = gh issue list --state all --limit 100 --json number,title | ConvertFrom-Json

foreach ($i in $issues) {
    if ($issueTitles.ContainsKey($i.title)) {
        $new = $issueTitles[$i.title]
        gh issue edit $i.number --title "$new" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    #$($i.number)  $new" -ForegroundColor Green
        } else {
            Write-Host "    FAILED  #$($i.number)" -ForegroundColor Red
        }
    }
}

# --- setup issue ------------------------------------------------------

Write-Host ""
Write-Host "==> Repository setup issue"

$setupTitle = "Set up the repository structure"
$current = @(gh issue list --state all --limit 100 --json title --jq ".[].title")

if ($current -contains $setupTitle) {
    Write-Host "    exists   $setupTitle" -ForegroundColor DarkGray
} else {
    $body = @"
Bring the existing model work into version control and set up the repository
so every later branch has somewhere to live.

Done when:
- [ ] Folder structure in place
- [ ] .gitignore blocking datasets, model weights and secrets
- [ ] .gitattributes keeping shell scripts in Unix line endings
- [ ] CONTRIBUTING.md recording the commit, branch and PR conventions
- [ ] Issue and pull request templates added
- [ ] Two-week delivery plan committed
"@
    gh issue create --title $setupTitle --body $body `
        --milestone "Phase 1: Model and Dataset" --label "docs" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    created  $setupTitle" -ForegroundColor Green
    } else {
        Write-Host "    FAILED   $setupTitle" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Current issues:"
gh issue list --limit 30
