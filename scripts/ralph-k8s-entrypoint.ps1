#!/usr/bin/env pwsh
# ralph-k8s-entrypoint.ps1 — Agency-powered Ralph for K8s CronJobs
# Runs a SINGLE Ralph round using GitHub Copilot CLI and exits.
# K8s CronJob handles scheduling (every 5 minutes).
#
# Required env vars:
#   GH_TOKEN            — GitHub PAT with repo, issues, copilot scopes
#   GITHUB_REPOSITORY   — owner/repo format
#
# Optional:
#   RALPH_LOG_LEVEL     — info (default), debug, error
#   SQUAD_AGENT_MODEL   — Copilot model (default: claude-sonnet-4.5)

$ErrorActionPreference = "Stop"

$ts = { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
$logLevel = $env:RALPH_LOG_LEVEL ?? "info"
$repo = $env:GITHUB_REPOSITORY
$model = $env:SQUAD_AGENT_MODEL ?? "claude-sonnet-4.5"
$machineId = $env:HOSTNAME ?? $env:COMPUTERNAME ?? "k8s-pod"

function Write-Log {
    param([string]$Level, [string]$Message)
    if ($Level -eq "debug" -and $logLevel -ne "debug") { return }
    Write-Host "[$(& $ts)] [$Level] $Message"
}

# ── Preflight checks ──────────────────────────────────────────────────────────
Write-Log "info" "Ralph K8s starting — machine=$machineId repo=$repo model=$model"

if (-not $env:GH_TOKEN) {
    Write-Log "error" "GH_TOKEN not set. Cannot authenticate with GitHub."
    exit 1
}
if (-not $repo) {
    Write-Log "error" "GITHUB_REPOSITORY not set. Format: owner/repo"
    exit 1
}

# ── Authenticate gh CLI ───────────────────────────────────────────────────────
Write-Log "info" "Verifying GitHub auth..."
try {
    $user = gh api user --jq '.login' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "error" "GitHub authentication failed: $user"
        exit 1
    }
    Write-Log "info" "GitHub auth OK — user: $user"
} catch {
    Write-Log "error" "GitHub auth exception: $_"
    exit 1
}

# ── Check for Agency CLI or Copilot CLI ────────────────────────────────────────
$useAgency = $false
$agencyVersion = agency --version 2>&1
if ($LASTEXITCODE -eq 0) {
    $useAgency = $true
    Write-Log "info" "Agency CLI: $($agencyVersion | Select-Object -First 1)"
} else {
    # Fall back to gh copilot
    $ghCopilot = gh copilot --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "error" "Neither Agency CLI nor gh copilot found. Install one to enable AI agent execution."
        Write-Log "info" "Falling back to basic issue polling mode..."
        # Run the basic ralph-watch.ps1 as fallback
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        & "$scriptDir/ralph-watch.ps1"
        exit $LASTEXITCODE
    }
    Write-Log "info" "Using gh copilot: $($ghCopilot | Select-Object -First 1)"
}

# ── Clone repo (if not already present) ────────────────────────────────────────
$repoDir = "/tmp/squad-repo"
if (-not (Test-Path "$repoDir/.git")) {
    Write-Log "info" "Cloning $repo..."
    git clone --depth 1 "https://x-access-token:$($env:GH_TOKEN)@github.com/$repo.git" $repoDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "error" "Failed to clone $repo"
        exit 1
    }
} else {
    Write-Log "info" "Repo already cloned, pulling latest..."
    Set-Location $repoDir
    git pull --ff-only 2>&1 | Out-Null
}
Set-Location $repoDir

# ── Build the prompt ──────────────────────────────────────────────────────────
$prompt = @"
You are Ralph, the Squad work monitor. Scan the GitHub project board and work on issues.

RULES:
1. Check open issues with squad labels
2. For each unassigned issue: claim it (assign to @me), then work on it
3. Create PRs for completed work
4. Close done items older than 3 days
5. Reconcile board state with issue state
6. MAXIMIZE PARALLELISM — spawn multiple agents for independent issues

MULTI-MACHINE COORDINATION:
- Before working on ANY issue, check if it's already assigned
- If assigned to someone else, SKIP IT
- Claim issues before starting: gh issue edit <number> --add-assignee "@me"
"@

# ── Run the AI agent round ────────────────────────────────────────────────────
Write-Log "info" "Starting AI agent round..."
$startTime = Get-Date

try {
    if ($useAgency) {
        $output = agency copilot --yolo --no-ask-user --model $model -p $prompt 2>&1
    } else {
        # gh copilot fallback (more limited)
        $output = gh copilot suggest "$prompt" 2>&1
    }
    $exitCode = $LASTEXITCODE
    $duration = ((Get-Date) - $startTime).TotalSeconds

    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -eq 0) {
        Write-Log "info" "Round completed successfully in $([math]::Round($duration, 1))s"
    } else {
        Write-Log "error" "Round failed with exit code $exitCode after $([math]::Round($duration, 1))s"
    }
} catch {
    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-Log "error" "Round exception after $([math]::Round($duration, 1))s: $_"
    $exitCode = 1
}

Write-Log "info" "Ralph K8s round complete — exit=$exitCode duration=$([math]::Round($duration, 1))s"
exit $exitCode
