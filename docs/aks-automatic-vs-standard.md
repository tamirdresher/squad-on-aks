# AKS Automatic vs Standard for Squad

## TL;DR

**Use AKS Standard** for dev/staging (lower quota requirements). **Use AKS Automatic** for production (less ops overhead, built-in KEDA).

## Comparison

| Aspect | AKS Standard | AKS Automatic |
|--------|-------------|---------------|
| **Minimum quota** | 2 vCPUs (1 node) | 16 vCPUs (3 AZs) |
| **KEDA** | Manual addon install | ✅ Built-in |
| **Karpenter** | Not available | ✅ Built-in |
| **VPA** | Manual install | ✅ Built-in |
| **Node management** | You size and manage pools | Auto-managed |
| **Security** | You configure RBAC, policies | Hardened defaults |
| **Key Vault CSI** | Manual addon | ✅ Built-in |
| **Workload Identity** | Manual OIDC setup | ✅ Pre-configured |
| **Monitoring** | Manual Log Analytics setup | ✅ Azure Monitor integrated |
| **Auto-patching** | Manual maintenance windows | ✅ Automatic |
| **Pricing** | Pay for provisioned VMs | Usage-based, bin-packed |

## Why We Chose Standard (Initially)

Our enterprise subscription had a **16 vCPU quota limit** that blocked AKS Automatic. With Standard:
- Created with 1x Standard_D2_v2 (2 vCPUs)
- Total cost: ~$0.10/hour for the single node
- Can scale later when needed

## When to Use Automatic

AKS Automatic is the better choice when you have:
- ✅ Sufficient quota (≥16 vCPUs)
- ✅ Production workload
- ✅ Want minimal Kubernetes management
- ✅ Need built-in KEDA for autoscaling
- ✅ Multiple agent types with different resource needs (Karpenter auto-sizes)

## Migration Path

Start with Standard, migrate to Automatic when ready:

```bash
# 1. Create Automatic cluster
az aks create --sku automatic --name squad-aks-prod

# 2. Same Helm chart works on both
helm upgrade --install squad-agents ./helm/squad-agents \
  --set global.acrLoginServer=$ACR.azurecr.io

# 3. Delete Standard cluster
az aks delete --name squad-aks-dev
```

The Helm chart is cluster-agnostic. No changes needed between Standard and Automatic.
