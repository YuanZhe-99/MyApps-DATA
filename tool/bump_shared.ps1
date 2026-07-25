# Purpose: Check out a tagged myapps_data release in every sibling app checkout and
#          print the pointer-bump commands.
# Inputs:  -Tag <vX.Y.Z> (required); -Root <path> (default: parent of this repo);
#          -Apps <names> (default: MyAnime, MyDay, MyDevice); -Verify to run analyze+test.
# Returns: Exit code 0 when every app was updated; 1 when any app failed.
# Side effects: Fetches in each app's submodule and checks out the tag there. Does NOT
#          commit, and does NOT push — it prints the commands for you to run.
# Notes:   Deliberately stops short of committing. A pointer bump should be verified and
#          committed deliberately, and the apps do not share a branch name.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [string]$Root,

    [string[]]$Apps = @('MyAnime', 'MyDay', 'MyDevice'),

    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
    # Default: the workspace root holding this repo and the sibling app checkouts.
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Write-Host "Bumping myapps_data to $Tag" -ForegroundColor Cyan
Write-Host "Workspace root: $Root"
Write-Host ''

$failed = @()
$updated = @()

foreach ($app in $Apps) {
    $appPath = Join-Path $Root $app
    $subPath = Join-Path $appPath 'packages/myapps_data'

    Write-Host "=== $app ===" -ForegroundColor Yellow

    if (-not (Test-Path $subPath)) {
        Write-Host "  skipped: $subPath not found (submodule not initialized?)" -ForegroundColor Red
        $failed += $app
        continue
    }

    try {
        git -C $subPath fetch origin --tags --quiet
        if (-not $?) { throw 'fetch failed' }

        git -C $subPath checkout --quiet $Tag
        if (-not $?) { throw "checkout $Tag failed" }

        $at = git -C $subPath describe --tags
        Write-Host "  submodule now at: $at"

        if ($Verify) {
            Write-Host '  running flutter analyze + test…'
            Push-Location $appPath
            try {
                flutter pub get 2>&1 | Out-Null
                $analyze = flutter analyze 2>&1 | Select-Object -Last 1
                $test = flutter test 2>&1 | Select-Object -Last 1
                Write-Host "  analyze: $analyze"
                Write-Host "  test:    $test"
            } finally {
                Pop-Location
            }
        }

        $updated += $app
    } catch {
        Write-Host "  FAILED: $_" -ForegroundColor Red
        $failed += $app
    }

    Write-Host ''
}

if ($updated.Count -gt 0) {
    Write-Host 'Submodules updated. Review, then commit and push each app:' -ForegroundColor Green
    Write-Host ''
    foreach ($app in $updated) {
        $appPath = Join-Path $Root $app
        # The apps do NOT share a branch name — MyAnime and MyDevice are on `master`,
        # MyDay is on `main`. Push HEAD rather than a hardcoded branch, or a scripted
        # push silently fails on the odd one out.
        $branch = git -C $appPath branch --show-current
        Write-Host "cd `"$appPath`"" -ForegroundColor Gray
        Write-Host "git add packages/myapps_data" -ForegroundColor Gray
        Write-Host "git commit -m `"Bump myapps_data to $Tag`"" -ForegroundColor Gray
        Write-Host "git push origin HEAD   # branch: $branch" -ForegroundColor Gray
        Write-Host "git push github HEAD" -ForegroundColor Gray
        Write-Host ''
    }
    Write-Host 'Verify afterwards with: git ls-remote <remote> refs/heads/<branch>' -ForegroundColor Gray
}

if ($failed.Count -gt 0) {
    Write-Host "Failed: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

exit 0
