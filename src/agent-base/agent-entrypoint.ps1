# agent-entrypoint.ps1 — Long-running Squad agent for K8s Deployment
# Runs continuously, picking up work dispatched by the coordinator.
#
# Required env vars:
#   GH_TOKEN            — GitHub PAT
#   GITHUB_REPOSITORY   — owner/repo format
#
# Optional:
#   SQUAD_AGENT_TYPE    — agent type (default: picard)
#   SQUAD_MODEL         — Copilot model override
#   AGENT_IDLE_TIMEOUT  — seconds to wait between checks (default: 60)

$ErrorActionPreference = "Stop"

$ts = { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
$repo = $env:GITHUB_REPOSITORY
$model = $env:SQUAD_MODEL ?? "claude-sonnet-4.5"
$agentType = $env:SQUAD_AGENT_TYPE ?? "picard"
$idleTimeout = [int]($env:AGENT_IDLE_TIMEOUT ?? "60")
$machineId = $env:HOSTNAME ?? "k8s-agent"

function Write-Log {
    param([string]$Level, [string]$Message)
    Write-Host "[$(& $ts)] [$Level] [$agentType] $Message"
}

# ── Preflight ──
Write-Log "info" "Agent starting — type=$agentType machine=$machineId repo=$repo model=$model"

if (-not $env:GH_TOKEN) { Write-Log "error" "GH_TOKEN not set"; exit 1 }
if (-not $repo) { Write-Log "error" "GITHUB_REPOSITORY not set"; exit 1 }

# Verify auth
$user = gh api user --jq '.login' 2>&1
if ($LASTEXITCODE -ne 0) { Write-Log "error" "GitHub auth failed: $user"; exit 1 }
Write-Log "info" "GitHub auth OK — user: $user"

# Detect Copilot CLI
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
        Write-Log "error" "No Copilot CLI found"; exit 1
    }
}

# Clone repo
$repoDir = "/tmp/squad-repo"
if (-not (Test-Path "$repoDir/.git")) {
    git clone --depth 1 "https://x-access-token:$($env:GH_TOKEN)@github.com/$repo.git" $repoDir 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Log "error" "Clone failed"; exit 1 }
}

# Mark ready for health check
"ready" | Set-Content /tmp/agent-ready

# ── Main loop ──
Write-Log "info" "Agent ready, entering work loop..."
while ($true) {
    try {
        Set-Location $repoDir
        git pull --ff-only 2>&1 | Out-Null

        # Check for assigned issues that need work
        $issues = gh issue list --repo $repo --assignee $user --label "squad-in-progress" --json number,title --jq '.[].number' 2>&1
        
        if ($issues -and $issues.Count -gt 0) {
            foreach ($issueNum in $issues) {
                Write-Log "info" "Working on issue #$issueNum"
                
                $prompt = "You are a Squad agent working on issue #$issueNum in $repo. Read the issue, understand the requirements, implement the solution, create a branch squad/$issueNum, commit your changes, push, and create a PR. Be thorough and test your work."
                
                $sessionId = [guid]::NewGuid().ToString()
                if ($useAgency) {
                    agency copilot --yolo --no-ask-user --agent squad --model $model -p $prompt --resume=$sessionId 2>&1 | ForEach-Object { Write-Host $_ }
                } else {
                    gh copilot suggest "$prompt" --shell 2>&1 | ForEach-Object { Write-Host $_ }
                }
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "info" "Issue #$issueNum completed successfully"
                } else {
                    Write-Log "warn" "Issue #$issueNum failed with exit code $LASTEXITCODE"
                }
            }
        } else {
            Write-Log "debug" "No assigned work found, idling..."
        }
    } catch {
        Write-Log "error" "Loop error: $_"
    }

    Start-Sleep -Seconds $idleTimeout
}
