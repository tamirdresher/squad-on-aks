# Troubleshooting — Squad on AKS

Common issues and their fixes, collected from real deployments.

## Pod Issues

### Pod stuck in `ContainerCreating`

**Symptom:** Pod never reaches `Running`, stays in `ContainerCreating` for minutes.

**Cause:** Usually the CSI secrets store driver trying to mount a volume that doesn't exist.

```bash
kubectl describe pod <pod-name> -n squad
# Look for: MountVolume.SetUp failed for volume "secrets-store"
```

**Fix:** Either:
1. Set up Azure Key Vault and the SecretProviderClass, OR
2. Deploy without Key Vault: `--set global.keyVaultName=""`

### Pod stuck in `Pending`

**Symptom:** Pod never gets scheduled to a node.

```bash
kubectl describe pod <pod-name> -n squad
# Look for: "didn't match Pod's node affinity/selector"
```

**Fix:** Your cluster doesn't have the labeled node pool. Either:
1. Remove nodeSelector: set `ralph.nodeSelector={}` in values.yaml
2. Add the node pool: `az aks nodepool add --name squadmonitor --labels squad.github.com/pool=monitor`

### Pod crashes with `Error` / `CrashLoopBackOff`

**Symptom:** Pod starts but immediately exits.

```bash
kubectl logs <pod-name> -n squad
```

**Common causes:**
- `GH_TOKEN` is empty/invalid → Check the secret: `kubectl get secret squad-runtime-secrets -n squad -o jsonpath='{.data.GH_TOKEN}' | base64 -d`
- `ralph-watch.ps1` script error → Check logs for PowerShell errors
- GitHub API rate limited → Wait or use a GitHub App token (higher limits)

## Helm Issues

### "invalid label value" on install

**Symptom:**
```
metadata.labels: Invalid value: "org/repo": a valid label must consist of alphanumeric characters...
```

**Cause:** Repository name with `/` used as a K8s label value.

**Fix:** Already handled in chart (`replace "/" "_"`). If you see this, update to latest chart version.

### "Namespace exists and cannot be imported"

**Symptom:** Helm refuses to install because the namespace already exists.

**Cause:** You created the namespace manually before Helm.

**Fix:**
```bash
kubectl delete namespace squad
helm upgrade --install squad-agents ./helm/squad-agents --create-namespace --namespace squad
```

### Duplicate env var warnings

**Symptom:**
```
Warning: spec.containers[0].env[5]: hides previous definition of "SQUAD_AGENT_TYPE"
```

**Cause:** Same env var defined both in template and in `ralph.env` values.

**Fix:** Don't add `SQUAD_AGENT_TYPE` or `GITHUB_REPOSITORY` to `ralph.env` — they're hardcoded in the template.

## Azure Issues

### "VM size not allowed in your subscription"

**Symptom:** `az aks create` fails with BadRequest.

**Cause:** Enterprise subscriptions often restrict which VM SKUs can be used.

**Fix:**
```bash
# Check what's allowed
az aks create --resource-group mygroup --name test --node-vm-size Standard_D2s_v5 2>&1 | grep "available VM sizes"
# The error message lists allowed sizes
```

### AKS Automatic quota error

**Symptom:** `az aks create --sku automatic` needs 16 vCPUs.

**Cause:** AKS Automatic requires minimum 3 nodes across availability zones.

**Fix:** Use AKS Standard with `--node-count 1` for dev. AKS Automatic is better for production.

### ACR build takes forever

**Symptom:** `az acr build` uploads for 10+ minutes.

**Cause:** The entire build context (your repo) is uploaded to Azure.

**Fix:** Create a minimal build context:
```bash
mkdir .build-context
cp Dockerfile ralph-watch.ps1 squad.config.ts .build-context/
az acr build --registry $ACR --image squad-ralph:latest .build-context/
```

Or add a `.dockerignore`:
```
*.mp3
*.wav
*.png
*.pdf
node_modules/
.git/
```

### `az login` device code blocked

**Symptom:** `az login --use-device-code` fails with Conditional Access error.

**Cause:** Org policy blocks device code authentication flow.

**Fix:** Use browser-based login: `az login` (no `--use-device-code`). If that doesn't work either, ask your Azure admin about Conditional Access policies.

## KEDA Issues

### ScaledObject not scaling

**Symptom:** KEDA is installed but pods don't scale.

**Check:**
```bash
# Verify KEDA is running
kubectl get pods -n kube-system | grep keda

# Check ScaledObject status
kubectl describe scaledobject picard-scaler -n squad

# Check KEDA operator logs
kubectl logs -n kube-system -l app=keda-operator --tail=50
```

**Common causes:**
- KEDA add-on not installed: `az aks update --resource-group $RG --name $CLUSTER --enable-keda`
- `keda.enabled: false` in values.yaml
- GitHub token doesn't have required scopes
