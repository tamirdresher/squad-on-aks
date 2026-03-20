#!/usr/bin/env pwsh
# ralph-watch.ps1 — Squad Work Monitor
#
# This script polls GitHub issues and dispatches work to agents.
# It's designed to run as a CronJob in Kubernetes (every 5 minutes).
#
# Required environment variables:
#   GH_TOKEN            — GitHub personal access token
#   GITHUB_REPOSITORY   — owner/repo format
#   SQUAD_AGENT_TYPE    — "ralph" (set by container)
#
# Optional:
#   SQUAD_LOG_LEVEL     — "info" (default), "debug", "error"

$ErrorActionPreference = "Stop"

# --- Configuration ---
$repo = $env:GITHUB_REPOSITORY
$logLevel = $env:SQUAD_LOG_LEVEL ?? "info"

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($Level -eq "debug" -and $logLevel -ne "debug") { return }
    Write-Host "[$ts] [$Level] $Message"
}

# --- Preflight ---
if (-not $env:GH_TOKEN) {
    Write-Log "error" "GH_TOKEN not set. Cannot authenticate with GitHub."
    exit 1
}
if (-not $repo) {
    Write-Log "error" "GITHUB_REPOSITORY not set. Format: owner/repo"
    exit 1
}

Write-Log "info" "Ralph starting — monitoring $repo"

# --- Check auth ---
try {
    $authStatus = gh auth status 2>&1
    Write-Log "debug" "Auth: $authStatus"
} catch {
    Write-Log "error" "GitHub CLI auth failed: $_"
    exit 1
}

# --- Lock file (prevent overlapping runs in K8s) ---
$lockDir = $env:SQUAD_LOCK_DIR ?? "/tmp/squad"
$lockFile = Join-Path $lockDir "ralph.lock"

if (-not (Test-Path $lockDir)) {
    New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
}

if (Test-Path $lockFile) {
    $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($lockAge.TotalMinutes -lt 4) {
        Write-Log "info" "Another Ralph is running (lock age: $($lockAge.TotalMinutes)m). Exiting."
        exit 0
    }
    Write-Log "info" "Stale lock file detected. Removing."
    Remove-Item $lockFile -Force
}

# Create lock
Set-Content -Path $lockFile -Value (Get-Date -Format "o")

try {
    # --- Fetch open issues ---
    Write-Log "info" "Fetching open issues..."

    $issues = gh issue list --repo $repo --state open --json number,title,labels,assignees --limit 50 | ConvertFrom-Json

    if (-not $issues -or $issues.Count -eq 0) {
        Write-Log "info" "No open issues. Nothing to do."
        exit 0
    }

    Write-Log "info" "Found $($issues.Count) open issues"

    # --- Find unassigned issues ---
    $unassigned = $issues | Where-Object { $_.assignees.Count -eq 0 }
    Write-Log "info" "Unassigned: $($unassigned.Count)"

    foreach ($issue in $unassigned) {
        $labels = ($issue.labels | ForEach-Object { $_.name }) -join ", "
        Write-Log "info" "  #$($issue.number): $($issue.title) [$labels]"

        # Route based on labels (customize this for your team)
        $agentLabel = $issue.labels | Where-Object { $_.name -like "squad:*" } | Select-Object -First 1

        if ($agentLabel) {
            $agent = $agentLabel.name -replace "^squad:", ""
            Write-Log "info" "  → Routing to agent: $agent"

            # Assign the issue to the agent
            # In production, this would create a K8s Job or trigger a workflow
            gh issue edit $issue.number --repo $repo --add-label "squad:in-progress"
        } else {
            Write-Log "debug" "  → No squad label, skipping"
        }
    }

    Write-Log "info" "Ralph cycle complete."

} finally {
    # Clean up lock file
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
}
