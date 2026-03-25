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
try {
    $agencyBin = Get-Command agency -ErrorAction SilentlyContinue
    if ($agencyBin) {
        $useAgency = $true
        Write-Log "info" "Agency CLI found at: $($agencyBin.Source)"
    }
} catch { }

if (-not $useAgency) {
    try {
        $ghCopilotCheck = gh extension list 2>&1 | Select-String "copilot"
        if ($ghCopilotCheck) {
            Write-Log "info" "gh copilot extension found"
        } else {
            Write-Log "warn" "No Copilot CLI found — will use gh CLI directly for issue management"
        }
    } catch {
        Write-Log "warn" "Copilot CLI detection failed — will use gh CLI directly"
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

# ── Run Ralph round ──
Write-Log "info" "Starting Ralph round..."
$startTime = Get-Date

try {
    if ($useAgency) {
        # Agency CLI — full autonomous Copilot session
        $promptFile = "/tmp/ralph-prompt.txt"
        [System.IO.File]::WriteAllText($promptFile, $prompt, [System.Text.Encoding]::UTF8)
        $roundSessionId = [guid]::NewGuid().ToString()
        $promptText = [System.IO.File]::ReadAllText($promptFile)
        $output = agency copilot --yolo --no-ask-user --agent squad --model $model -p $promptText --resume=$roundSessionId 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
    } else {
        # Direct gh CLI — scan issues and manage board
        Write-Log "info" "Using gh CLI for issue management..."
        
        # List open unassigned issues with squad label
        $openIssues = gh issue list --repo $repo --label "squad" --state open --json number,title,assignees --jq '.[] | select(.assignees | length == 0) | "\(.number)\t\(.title)"' 2>&1
        if ($openIssues) {
            Write-Log "info" "Found unassigned squad issues:"
            $openIssues | ForEach-Object {
                Write-Log "info" "  $_"
                $issueNum = ($_ -split "`t")[0]
                # Claim the issue
                gh issue edit $issueNum --repo $repo --add-assignee "@me" 2>&1 | Out-Null
                gh issue comment $issueNum --repo $repo --body "Ralph K8s pod $machineId claiming this issue at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')" 2>&1 | Out-Null
                # Add in-progress label
                gh issue edit $issueNum --repo $repo --add-label "squad-in-progress" 2>&1 | Out-Null
                Write-Log "info" "  Claimed #$issueNum"
            }
        } else {
            Write-Log "info" "No unassigned squad issues found"
        }
        
        # Check for stale done items (issues closed >3 days ago still with squad label)
        $closedIssues = gh issue list --repo $repo --label "squad-in-progress" --state closed --json number,closedAt --jq '.[].number' 2>&1
        if ($closedIssues) {
            $closedIssues | ForEach-Object {
                gh issue edit $_ --repo $repo --remove-label "squad-in-progress" 2>&1 | Out-Null
                Write-Log "info" "  Cleaned up closed issue #$_"
            }
        }
        
        $exitCode = 0
    }
    
    $duration = ((Get-Date) - $startTime).TotalSeconds

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
