# 🚀 Squad on AKS

Deploy autonomous AI agent squads on **Azure Kubernetes Service (AKS)** and **Azure Container Apps (ACA)**.

## What Is This?

[Squad](https://github.com/tamirdresher/squad) is a framework for orchestrating teams of AI agents that collaborate on software engineering tasks — reading code, writing PRs, running tests, and monitoring work queues. This repo packages Squad for cloud deployment so your AI team runs 24/7.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  AKS / ACA                  │
│                                             │
│  ┌──────────────┐    ┌──────────────────┐   │
│  │  Coordinator  │───▶│  Agent Pool      │   │
│  │  (Picard)     │    │  ┌────┐ ┌────┐  │   │
│  └──────┬───────┘    │  │Data│ │Worf│  │   │
│         │            │  └────┘ └────┘  │   │
│         │            │  ┌─────┐┌─────┐ │   │
│         │            │  │Seven││Troi │ │   │
│         │            │  └─────┘└─────┘ │   │
│         │            └──────────────────┘   │
│  ┌──────▼───────┐                           │
│  │  Ralph        │  ← Persistent pod /      │
│  │  (Work Queue) │    CronJob monitor       │
│  └──────────────┘                           │
│                                             │
│  ┌──────────────┐    ┌──────────────────┐   │
│  │  Aspire       │    │  Azure Key Vault │   │
│  │  Dashboard    │    │  (Secrets)       │   │
│  └──────────────┘    └──────────────────┘   │
└─────────────────────────────────────────────┘
```

### Components

| Component | Container | Role |
|-----------|-----------|------|
| **Coordinator** | `squad-coordinator` | Routes issues to agents, orchestrates multi-agent tasks |
| **Agents** | `squad-agent-{name}` | Specialized workers (code, infra, security, docs) |
| **Ralph** | `squad-ralph` | Persistent work queue monitor — watches ADO/GitHub for new items |
| **Dashboard** | `squad-dashboard` | .NET Aspire dashboard for observability |

## Deployment Tiers

### 🆓 Tier 1: Free (ACA Free Tier)
- Azure Container Apps free tier (180K vCPU-seconds/month)
- Single coordinator + 2-3 agents
- Free GitHub Copilot account for agent completions
- **Cost: $0/month** (within free limits)

### 💰 Tier 2: Scale (AKS with Spot)
- AKS cluster with spot node pools
- Helm chart for declarative deployment
- KEDA auto-scaling based on issue queue depth
- Multi-squad support (multiple repos)
- **Cost: ~$30-80/month** (spot instances)

### 🏢 Tier 3: Production
- Azure Key Vault for secrets management
- Managed identity authentication
- Multi-repo, multi-squad orchestration
- Full Aspire observability + alerting
- **Cost: $100-300/month**

## Quick Start

### Prerequisites
- Azure CLI (`az`)
- Docker
- `gh` CLI (authenticated)
- Node.js 20+

### Deploy to ACA (Free Tier)

```bash
# 1. Login to Azure
az login

# 2. Create environment
./scripts/setup-aca.sh

# 3. Build and deploy
./scripts/deploy-aca.sh

# 4. Verify
./scripts/test-e2e.sh
```

### Deploy to AKS

```bash
# 1. Create AKS cluster
./scripts/setup-aks.sh

# 2. Install via Helm
helm install squad ./deploy/helm/squad \
  --set github.token=$GITHUB_TOKEN \
  --set github.org=tamirdresher

# 3. Verify
kubectl get pods -n squad
```

## Project Structure

```
squad-on-aks/
├── src/
│   ├── coordinator/      # Coordinator container (Picard)
│   ├── ralph/            # Work queue monitor container
│   └── agent-base/       # Base image for all agents
├── deploy/
│   ├── aca/              # Azure Container Apps configs
│   ├── aks/              # AKS cluster setup
│   └── helm/squad/       # Helm chart
├── scripts/              # Setup and deploy scripts
├── docs/                 # Architecture docs
└── .squad/               # Squad team configuration
```

## Roadmap

- [x] Project setup and planning
- [ ] **Phase 1**: Free tier deployment on ACA
- [ ] **Phase 2**: AKS scale-out with Helm + KEDA
- [ ] **Phase 3**: Production hardening

## Contributing

This project uses Squad itself! Issues labeled `squad` are automatically picked up by our AI agents. See [.squad/team.md](.squad/team.md) for the team configuration.

## License

MIT
