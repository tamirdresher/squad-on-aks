# Real Squad Containers

## Architecture

Squad-on-AKS runs the **real Squad system** — not lightweight stubs.
Each pod runs PowerShell 7 + GitHub CLI + Agency CLI (Copilot CLI).

### Components

| Component | Runtime | K8s Resource | Purpose |
|-----------|---------|-------------|---------|
| Ralph | PowerShell + Agency | CronJob (every 5min) | Polls GitHub issues, dispatches work |
| Agent (Picard) | PowerShell + Agency | Deployment (KEDA-scaled) | Picks up assigned issues, implements solutions |
| Coordinator | Node.js | Deployment | Webhook receiver, work routing |

### How It Works

1. **Ralph** runs as a K8s CronJob every 5 minutes
2. Each run: clones repo → scans open issues → claims unassigned `squad`-labeled issues
3. Ralph uses `agency copilot --yolo` to run a full Copilot session autonomously
4. **Agents** (Picard pods) run continuously, picking up issues assigned to them
5. Each agent uses Agency CLI to run Copilot sessions that implement solutions
6. Agents create branches (`squad/{issue}-{slug}`), commit, push, and open PRs

### Container Stack

All containers include:
- `mcr.microsoft.com/powershell:latest` — PowerShell 7 base
- Node.js 20 LTS — required by Agency CLI
- GitHub CLI (`gh`) — GitHub API access
- Agency CLI — runs Copilot sessions (installed via PathInstaller)
- `git`, `jq`, `curl` — standard tools

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GH_TOKEN` | Yes | GitHub PAT with repo, issues, PRs scope |
| `GITHUB_REPOSITORY` | Yes | `owner/repo` format |
| `SQUAD_AGENT_MODEL` | No | Copilot model (default: claude-sonnet-4.5) |
| `RALPH_LOG_LEVEL` | No | Log level: info, debug, error |
| `RALPH_INTERVAL_SECONDS` | No | Poll interval (default: 300) |
| `SQUAD_AGENT_TYPE` | No | Agent type (default: picard) |
| `SQUAD_CONFIG_PATH` | No | Path to squad.config.ts |

### Building

```bash
# Ralph
docker build -f src/ralph/Dockerfile -t squad-ralph:latest src/ralph/

# Agent
docker build -f src/agent-base/Dockerfile -t squad-agent:latest src/agent-base/

# Coordinator (still Node.js)
docker build -f src/coordinator/Dockerfile -t squad-coordinator:latest src/coordinator/
```

### Local Testing

```bash
# Test Ralph (single round)
docker run --rm \
  -e GH_TOKEN=$GH_TOKEN \
  -e GITHUB_REPOSITORY=your-org/your-repo \
  squad-ralph:latest

# Test Agent
docker run --rm \
  -e GH_TOKEN=$GH_TOKEN \
  -e GITHUB_REPOSITORY=your-org/your-repo \
  -e SQUAD_AGENT_TYPE=picard \
  squad-agent:latest
```
