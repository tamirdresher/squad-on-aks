# Copilot CLI Authentication for Kubernetes Pods

> How to make GitHub Copilot CLI (and Agency CLI) work inside containers running on AKS.

## The Challenge

The Ralph CronJob needs to run `copilot` or `agency copilot` commands inside a K8s pod. These tools require Copilot authentication, which is separate from the `GH_TOKEN` used for GitHub API access.

## Authentication Methods

### Method 1: GH_TOKEN with Copilot Access (Recommended)

If your GitHub account has Copilot access (Individual, Business, or Enterprise), the `GH_TOKEN` environment variable is sufficient:

```bash
# The GH_TOKEN must belong to a user with active Copilot license
export GH_TOKEN=ghp_your_copilot_enabled_token

# Verify Copilot access
gh copilot --version
```

**K8s Secret setup:**
```bash
kubectl create secret generic squad-runtime-secrets \
  --namespace squad \
  --from-literal=GH_TOKEN=ghp_your_copilot_enabled_token
```

### Method 2: Agency CLI with GH_TOKEN

The [Agency CLI](https://github.com/github/copilot-cli) (used in our production setup) authenticates via `GH_TOKEN`:

```bash
# Download Agency CLI binary
curl -L -o /usr/local/bin/agency \
  "https://github.com/github/copilot-cli/releases/latest/download/agency-linux-amd64"
chmod +x /usr/local/bin/agency

# Run with GH_TOKEN (set via K8s Secret)
agency copilot \
  --model claude-sonnet-4.5 \
  --yolo \
  --no-ask-user \
  -p "Scan the board and work on issues"
```

### Method 3: GitHub Copilot in CLI (Free Tier)

As of 2025, GitHub Copilot offers a free tier. Users can:
1. Sign up at [github.com/features/copilot](https://github.com/features/copilot)
2. Generate a PAT with Copilot scope
3. Use the token as `GH_TOKEN` in the container

**Note:** Free tier has rate limits (2,000 completions/month). For production Squad deployments, Copilot Business or Enterprise is recommended.

## Container Entrypoint

Our production entrypoint (`ralph-k8s-entrypoint.ps1`) does:

```powershell
# 1. Set GH_TOKEN from K8s Secret (mounted as env var)
# 2. Verify auth: gh api user
# 3. Clone the target repo
# 4. Run agency copilot with --yolo --no-ask-user
```

Key flags:
- `--model claude-sonnet-4.5` — specify the model explicitly
- `--yolo` — auto-approve file changes
- `--no-ask-user` — don't prompt for input (headless mode)

## Token Requirements

| Scope | Required For |
|-------|-------------|
| `repo` | Read/write issues, PRs, code |
| `workflow` | Trigger GitHub Actions |
| `copilot` | Copilot CLI access |
| `read:org` | Org repos (if applicable) |

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| "Copilot not available" | Token owner has no Copilot license | Upgrade to Copilot Individual/Business |
| "Model not found" | Default model unavailable | Add `--model claude-sonnet-4.5` flag |
| Auth loop in container | Using `gh auth login` (interactive) | Use `GH_TOKEN` env var instead |
| EMU token issues | Enterprise Managed User PAT format | Use `GH_TOKEN` env var, not `gh auth login` |
| 429 rate limits | Too many parallel agents | Reduce concurrency or implement rate governor |
