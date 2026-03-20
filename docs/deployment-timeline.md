# Deployment Timeline — Squad on AKS

> A real, unedited log of deploying Squad to AKS for the first time. Every failure, fix, and lesson learned — maintained for transparency and to help others avoid the same pitfalls.

## Session: March 20, 2026

### 13:30 — Azure Login (Attempt #5)

Previous attempts over two days:
- `az login --use-device-code` → **Blocked** by org Conditional Access policy
- `az login` (browser) → Browser opens but callback to localhost never completes (3 times)
- This time: `az login` finally worked. Browser auth succeeded.

**Two tenants failed** during multi-tenant auth:
- HMGAdmin: Conditional Access blocked token issuance
- ESME Prod: Refresh token expired (issued Sep 2025, max lifetime 24h)

**Lesson:** Enterprise Azure auth is unpredictable. Device code may be blocked. Browser callback may not work on DevBox. Be prepared to try multiple approaches.

### 13:35 — Finding the Right Subscription

The org has **1,121 Azure subscriptions**. Finding the right one:

```bash
# This is useless with 1000+ subs:
az account list --output table  # → wall of text

# This works:
az resource list --resource-group tamirdev --output table
# Found it by looking for resource groups with our name
```

**Lesson:** Always know your subscription ID upfront. With large orgs, `az account list` is almost unusable.

### 13:40 — AKS Cluster Creation: 4 Failures Before Success

**Attempt 1: AKS Automatic**
```bash
az aks create --sku automatic --location eastus
# FAILED: Needs 16 vCPUs across 3 AZs. Subscription quota insufficient.
```
AKS Automatic has a hard minimum of 16 vCPUs. Great for production, overkill for dev.

**Attempt 2: Standard with D2ds_v5**
```bash
az aks create --node-vm-size Standard_D2ds_v5
# FAILED: "VMCannotFitEphemeralOSDisk" — OS disk (128GB) > temp disk (75GB)
```
AKS defaults to ephemeral OS disk. Small VMs with small temp storage can't fit it.

**Attempt 3: Standard with DS2_v2**
```bash
az aks create --node-vm-size Standard_DS2_v2
# FAILED: "VM size not allowed in your subscription"
```
Enterprise subscriptions often restrict which VM SKUs can be used. The error message helpfully lists the allowed sizes.

**Attempt 4: Standard with D2_v2** ✅
```bash
az aks create --node-vm-size Standard_D2_v2 --node-count 1
# SUCCESS after ~8 minutes
```

**Lessons:**
1. Always run `az vm list-skus --location <loc>` before creating a cluster
2. AKS Automatic needs significant quota — don't assume it works in dev subscriptions
3. Read the error messages carefully — they tell you what IS allowed
4. Start with 1 node. You can always add more.

### 13:45 — ACR Created

```bash
az acr create --name squadacr --sku Basic --location eastus
# Done in 30 seconds. squadacr.azurecr.io ready.
```

No issues here. Basic SKU is plenty for dev.

### 14:17 — Cluster Ready

After 8 minutes: `squad-aks` running K8s 1.33.7, 1 node (Standard_D2_v2).

```bash
# Install kubectl (not pre-installed on DevBox)
az aks install-cli

# Get credentials
az aks get-credentials --resource-group tamirdev --name squad-aks
kubectl get nodes  # 1 node, Ready
```

### 14:25 — ACR Attach

```bash
az aks update --attach-acr squadacr
# Takes ~2 minutes (AAD role propagation)
```

This is required for AKS to pull images from your ACR without explicit credentials.

**Gotcha:** You can't run `az aks update` while the cluster has another operation in progress. Wait for create to fully complete.

### 14:28 — Docker Image Build (No Docker Needed!)

We don't have Docker installed on the DevBox. ACR cloud build to the rescue:

```bash
# First attempt: build from repo root
az acr build --registry squadacr --image squad-ralph:latest .
# ...waited 10 minutes, still uploading. Repo has 2GB of audio files.
# Killed it.

# Second attempt: minimal build context
mkdir build-context
cp squad.config.ts ralph-watch.ps1 build-context/
cp -r .squad/team.md .squad/routing.md build-context/.squad/
cp Dockerfile build-context/
az acr build --registry squadacr --image squad-ralph:latest --file Dockerfile build-context/
# Done in 2 minutes! Image: 233MB
```

**Lesson:** ACR cloud build uploads your entire build context. With large repos, create a minimal context directory or use `.dockerignore`.

### 14:35 — Helm Deploy: Label Bug

First deploy failed:
```
Namespace "squad" is invalid: metadata.labels: Invalid value:
"your-org/your-repo": must consist of alphanumeric characters, '-', '_' or '.'
```

**Root cause:** Kubernetes label values cannot contain `/`. Our `squad.github.com/repository` label had `owner/repo` format.

**Fix:** `{{ .Values.global.repository | replace "/" "_" }}` in `_helpers.tpl`

### 14:36 — CSI Driver Missing

Pod stuck in `ContainerCreating`:
```
MountVolume.SetUp failed: driver name secrets-store.csi.k8s.io not found
```

**Root cause:** The CronJob template always mounts the CSI volume, even when Key Vault isn't configured.

**Fix:** Made CSI volume conditional on `global.keyVaultName` being set.

### 14:40 — Node Selector Mismatch

Pod stuck in `Pending`:
```
0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector
```

**Root cause:** Values.yaml had `squad.github.com/pool: monitor` nodeSelector, but we only have the default node pool.

**Fix:** Disabled custom nodeSelectors in values.yaml defaults. Uncomment when dedicated pools exist.

### 14:48 — Duplicate Env Vars

```
Warning: spec.jobTemplate.spec.template.spec.containers[0].env[5]:
  hides previous definition of "SQUAD_AGENT_TYPE"
```

**Root cause:** `SQUAD_AGENT_TYPE` was both hardcoded in the template AND in `ralph.env` values.

**Fix:** Removed from values.yaml since it's hardcoded per-agent in templates.

### 14:51 — Ralph Running! 🎉

```bash
$ kubectl get cronjobs -n squad
NAME    SCHEDULE      SUSPEND   ACTIVE
ralph   */5 * * * *   False     0
```

CronJob deployed, secrets configured, pods scheduling. Ralph is alive on AKS.

---

## Total Time

| Phase | Duration |
|-------|----------|
| Azure login | ~15 min (including prior failures) |
| Subscription discovery | 5 min |
| AKS creation (including failures) | 20 min |
| ACR creation + attach | 5 min |
| Docker image build | 2 min |
| Helm chart fixes | 15 min |
| **Total** | **~60 min** |

## What We'd Do Differently

1. **Check VM SKU restrictions FIRST** — `az vm list-skus --location eastus --query "[?restrictions]"`
2. **Use `.dockerignore`** — Don't upload your whole repo to ACR build
3. **Test Helm locally** — `helm template` + `kubeval` before first deploy
4. **Start without Key Vault** — Get pods running, add CSI driver later
5. **Know your subscription ID** — Don't search through 1,121 subs at deploy time
