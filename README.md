# Squad on AKS — AI Agent Teams on Kubernetes

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AKS](https://img.shields.io/badge/Azure-AKS-blue)](https://learn.microsoft.com/azure/aks/)
[![Helm](https://img.shields.io/badge/Helm-v3-blue)](https://helm.sh)

Deploy **AI agent teams** to **Azure Kubernetes Service** using Helm, with Azure-native security (Workload Identity, Key Vault), KEDA autoscaling, and GitHub Actions CI/CD.

> **What is Squad?** An AI team framework where specialized agents (Lead, Frontend, Backend, Tester, Monitor) collaborate on GitHub issues. Ralph is the work monitor that polls for new issues and dispatches work. [Learn more →](docs/what-is-squad.md)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│                   AKS Cluster                    │
│                                                  │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │  Ralph        │    │  Agent Pods            │  │
│  │  (CronJob)    │───▶│  (spawned on demand)   │  │
│  │  */5 * * * *  │    │  Picard, Data, Worf... │  │
│  └──────┬───────┘    └────────────────────────┘  │
│         │                                        │
│  ┌──────▼───────┐    ┌────────────────────────┐  │
│  │  K8s Secrets  │◀───│  Key Vault CSI Driver  │  │
│  │  (GH_TOKEN)   │    │  (Workload Identity)   │  │
│  └──────────────┘    └────────────────────────┘  │
│                                                  │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │  KEDA         │    │  Prometheus Metrics    │  │
│  │  (autoscaler) │◀───│  (optional)            │  │
│  └──────────────┘    └────────────────────────┘  │
└─────────────────────────────────────────────────┘
         │                        │
         ▼                        ▼
   GitHub Issues            Azure Key Vault
   (work queue)             (secrets store)
```

**Key design decisions:**
- **Ralph = CronJob** — polls every 5 min, no always-on pod, `concurrencyPolicy: Forbid` replaces mutex
- **Agents = Jobs** — spawned on demand, terminated when done (cost efficient)
- **Secrets via Key Vault** — Workload Identity federation, no PATs in cluster
- **KEDA scaling** — scale-to-zero when no work, burst on demand

## ⚡ Quick Start

### Prerequisites

- Azure CLI (`az`) with an active subscription
- `kubectl` and `helm` v3
- A GitHub PAT with `repo`, `issues`, `workflow` scopes

### 1. Create Azure Resources

```bash
# Set your variables
RESOURCE_GROUP="myapp-rg"
LOCATION="eastus"
CLUSTER_NAME="squad-aks"
ACR_NAME="myappsquadacr"  # must be globally unique

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster (with security features)
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --node-count 1 \
  --node-vm-size Standard_D2s_v5 \
  --enable-managed-identity \
  --enable-addons azure-keyvault-secrets-provider \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --no-ssh-key

# Create container registry
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic

# Attach ACR to AKS (so AKS can pull images)
az aks update --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --attach-acr $ACR_NAME

# Get cluster credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
```

### 2. Build and Push the Docker Image

```bash
# Option A: Build in the cloud (no local Docker needed!)
az acr build --registry $ACR_NAME --image squad-ralph:latest --file docker/Dockerfile .

# Option B: Build locally
docker build -f docker/Dockerfile -t $ACR_NAME.azurecr.io/squad-ralph:latest .
docker push $ACR_NAME.azurecr.io/squad-ralph:latest
```

### 3. Create Secrets

```bash
# For development: plain K8s Secret
kubectl create namespace squad
kubectl create secret generic squad-runtime-secrets \
  --namespace squad \
  --from-literal=GH_TOKEN=ghp_your_token_here

# For production: use Azure Key Vault (see docs/key-vault-setup.md)
```

### 4. Deploy with Helm

```bash
helm upgrade --install squad-agents ./helm/squad-agents \
  --namespace squad \
  --create-namespace \
  --set global.acrLoginServer=$ACR_NAME.azurecr.io \
  --set global.repository=your-org/your-repo \
  --set ralph.image.repository=squad-ralph \
  --set ralph.image.tag=latest
```

### 5. Verify

```bash
# Check the CronJob
kubectl get cronjobs -n squad

# Manually trigger a test run
kubectl create job ralph-test --from=cronjob/ralph -n squad

# Check logs
kubectl logs -l job-name=ralph-test -n squad --follow
```

## 📁 Repository Structure

```
squad-on-aks/
├── README.md                          # You are here
├── helm/
│   ├── squad/                         # Core Squad chart (coordinator + Ralph Deployment)
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _helpers.tpl
│   │       ├── configmap.yaml         # squad.config.ts + team/routing ConfigMap
│   │       ├── deployment.yaml        # Ralph Deployment (lightweight alternative)
│   │       ├── ralph-deployment.yaml  # Ralph Deployment (full, with emptyDir scratch)
│   │       ├── secret.yaml            # Optional K8s Secret (use Key Vault in prod)
│   │       └── service.yaml           # Ralph metrics/health Service
│   └── squad-agents/                  # AKS-native chart (Ralph CronJob + Picard Deployment)
│       ├── Chart.yaml
│       ├── values.yaml                # ACR, Key Vault, KEDA, Workload Identity config
│       └── templates/
│           ├── _helpers.tpl
│           ├── namespace.yaml         # Squad namespace with Workload Identity label
│           ├── serviceaccount.yaml    # Workload Identity ServiceAccount
│           ├── rbac.yaml              # Agent job spawning permissions
│           ├── secret-provider-class.yaml  # Key Vault CSI integration
│           ├── ralph-cronjob.yaml     # Ralph work monitor (CronJob)
│           ├── picard-deployment.yaml # Lead agent Deployment + inline KEDA ScaledObject
│           └── picard-scaledobject.yaml # Composite AND KEDA ScaledObject (Tier 2)
├── keda/
│   ├── github-rate-scaler.yaml        # TriggerAuthentication for GitHub API
│   └── squad-scaledobject.yaml        # Standalone KEDA ScaledObject (3 triggers)
├── infrastructure/
│   ├── aks-automatic-squad.bicep      # AKS Automatic cluster + ACR + VNet + Log Analytics
│   └── aks-automatic-squad.bicepparam # Default parameters (dev environment)
├── docker/
│   └── Dockerfile                     # Multi-stage: PowerShell 7 + Node.js + gh CLI
├── scripts/
│   └── ralph-watch.ps1                # Ralph's polling loop
├── .github/
│   └── workflows/
│       └── deploy.yml                 # Build → Push → Deploy pipeline
├── docs/
│   ├── what-is-squad.md               # Squad framework overview
│   ├── deployment-timeline.md         # Real deployment log (warts and all)
│   ├── key-vault-setup.md             # Production secrets guide
│   ├── keda-scaling.md                # Autoscaling with KEDA
│   ├── aks-automatic-vs-standard.md   # AKS SKU comparison
│   └── troubleshooting.md             # Common issues and fixes
├── examples/
│   ├── values-dev.yaml                # Development overrides
│   └── values-prod.yaml               # Production overrides
└── LICENSE
```

## ⚠️ Warnings & Gotchas

> **Read this before deploying.** These are real issues we hit during our first deployment.

### 🔴 Critical

| Issue | What Happens | Fix |
|-------|-------------|-----|
| **K8s label `/` in repo name** | Helm install fails with "invalid label value" | Chart uses `replace "/" "_"` — already handled |
| **CSI driver without Key Vault** | Pod stuck in `ContainerCreating` forever | Set `global.keyVaultName=""` to skip CSI volumes |
| **No Docker locally** | Can't build image on Azure DevBox/Codespace | Use `az acr build` for cloud builds |
| **Enterprise VM restrictions** | AKS create fails with "VM size not allowed" | Check `az vm list-skus --location <loc>` first |

### 🟡 Important

| Issue | What Happens | Fix |
|-------|-------------|-----|
| **AKS Automatic needs 16 vCPUs** | Creation fails on small/restricted subscriptions | Use AKS Standard with smaller VMs |
| **Duplicate env vars in CronJob** | K8s warning about hidden definitions | Don't override SQUAD_AGENT_TYPE in `ralph.env` |
| **ACR build uploads entire repo** | Build takes 30+ minutes with large repos | Use minimal build context or `.dockerignore` |
| **1000+ subscriptions** | `az account list` is slow, hard to find right sub | Use `--query` filter: `az account list --query "[?contains(name,'mysubname')]"` |

### 🟢 Notes

- **Node selectors** are disabled by default. Uncomment in `values.yaml` when you add dedicated node pools.
- **KEDA** is disabled by default. Enable after installing the KEDA add-on: `az aks update --enable-keda`
- **Picard** (lead agent) is a Deployment, not a CronJob. It stays running. Disable with `picard.enabled=false` for cost savings.
- **GH_TOKEN** needs `repo`, `issues`, `workflow` scopes minimum. For org repos, also needs `read:org`.

## 🏗️ Infrastructure as Code (Bicep)

The `infrastructure/` directory contains Bicep templates for provisioning a complete AKS Automatic cluster:

```bash
# Create resource group + deploy AKS Automatic cluster with ACR, VNet, Log Analytics
az deployment group create \
  --resource-group squad-aks-rg \
  --template-file infrastructure/aks-automatic-squad.bicep \
  --parameters infrastructure/aks-automatic-squad.bicepparam
```

AKS Automatic includes KEDA built-in, managed node pools with autoscaling, and Azure RBAC integration.

> **Note:** AKS Automatic requires 16+ vCPUs quota. If your subscription is limited, use AKS Standard instead (see [docs/aks-automatic-vs-standard.md](docs/aks-automatic-vs-standard.md)).

## 📊 KEDA Autoscaling

KEDA can scale Squad agents based on workload. The `keda/` directory has standalone ScaledObjects, and the Helm chart includes inline KEDA support:

| Tier | Trigger | Scaler | Effort |
|------|---------|--------|--------|
| **1. Queue-based** | Open GitHub issues with squad labels | Built-in `github` scaler | Config only |
| **2. Composite AND** | Issue count AND rate-limit headroom | `github` + `metrics-api` with `scalingModifiers.formula` | Config + metrics exporter |
| **3. Token-based** | Copilot token budget remaining | Custom Prometheus exporter | ~30 LOC |

See [docs/keda-scaling.md](docs/keda-scaling.md) for details.

## 🔐 Security Model

| Layer | Mechanism |
|-------|-----------|
| **Pod identity** | Azure Workload Identity (OIDC federation) |
| **Secrets** | Azure Key Vault via CSI driver (no secrets in YAML) |
| **RBAC** | Minimal Role: `batch/jobs` create + `pods/logs` read |
| **Container** | Non-root user, dropped capabilities, read-only where possible |
| **Network** | Private cluster option, no public ingress needed |
| **Image** | ACR with integrated vulnerability scanning |

## 🤝 Contributing

Contributions welcome! This project came from a real deployment — if you hit something we didn't document, please open an issue or PR.

## 📄 License

MIT — see [LICENSE](LICENSE).

---

*Built by deploying AI agents to production with GitHub Copilot CLI. The [deployment timeline](docs/deployment-timeline.md) documents every step, failure, and fix.*
