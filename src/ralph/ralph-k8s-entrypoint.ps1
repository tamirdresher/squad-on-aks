# ralph-k8s-entrypoint.ps1 — Container-optimized Ralph for K8s CronJobs
# Runs a SINGLE Ralph round and exits (K8s CronJob handles scheduling).
#
# Required env vars:
#   GH_TOKEN            — GitHub PAT (repo, issues, PRs scope)
#   GITHUB_REPOSITORY   — owner/repo format
#
# Optional:
#   RALPH_LOG_LEVEL     — info (default), debug, error
#   SQUAD_AGENT_MODEL   — Copilot model override

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

# ── Preflight checks ──
Write-Log "info" "Ralph K8s starting — machine=$machineId repo=$repo model=$model"

if (-not $env:GH_TOKEN) {
    Write-Log "error" "GH_TOKEN not set. Cannot authenticate with GitHub."
    exit 1
}
if (-not $repo) {
    Write-Log "error" "GITHUB_REPOSITORY not set. Format: owner/repo"
    exit 1
}

# ── Authenticate gh CLI ──
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

# ── Detect Copilot CLI ──
# Supports both 'agency' (internal) and 'gh copilot' (public)
$useAgency = $false
$agencyVersion = agency --version 2>&1
if ($LASTEXITCODE -eq 0) {
    $useAgency = $true
    Write-Log "info" "Agency CLI: $($agencyVersion | Select-Object -First 1)"
} else {
    $ghCopilot = gh copilot --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "info" "gh copilot: $($ghCopilot | Select-Object -First 1)"
    } else {
        Write-Log "error" "No Copilot CLI found. Install 'agency' or 'gh extension install github/gh-copilot'."
        exit 1
    }
}

# ── Clone repo ──
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

# ── Build the prompt ──
$prompt = @"
Ralph, Go! MAXIMIZE PARALLELISM: For every round, identify ALL actionable issues and spawn agents for ALL of them simultaneously as background tasks — do NOT work on issues one at a time.

MULTI-MACHINE COORDINATION: Before spawning an agent for ANY issue, check if it's already assigned:
1. Use ``gh issue view <number> --json assignees`` to check
2. If assigned — SKIP IT
3. If NOT assigned — claim it: ``gh issue edit <number> --add-assignee "@me"``
4. Use branch naming: ``squad/{issue}-{slug}``

DONE ITEMS ARCHIVING: Check for items in Done status > 3 days. Close the issue if still open.
BOARD RECONCILIATION: Fix mismatches between issue state and board column.
"@

# ── Run Copilot round ──
Write-Log "info" "Starting copilot round..."
$startTime = Get-Date

$promptFile = "/tmp/ralph-prompt.txt"
[System.IO.File]::WriteAllText($promptFile, $prompt, [System.Text.Encoding]::UTF8)

try {
    $roundSessionId = [guid]::NewGuid().ToString()
    $promptText = [System.IO.File]::ReadAllText($promptFile)

    if ($useAgency) {
        # Agency CLI (internal tool — full autonomous mode)
        $output = agency copilot --yolo --no-ask-user --agent squad --model $model -p $promptText --resume=$roundSessionId 2>&1
    } else {
        # gh copilot (public CLI — suggest mode)
        $output = gh copilot suggest "$promptText" --shell 2>&1
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
} finally {
    Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
}

Write-Log "info" "Ralph K8s round complete — exit=$exitCode duration=$([math]::Round($duration, 1))s"
exit $exitCode
