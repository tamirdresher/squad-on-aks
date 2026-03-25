# Identity Architecture — Squad on AKS

> Zero-secrets Kubernetes: no passwords in pods, no tokens in images, no credentials in git.

## The 5-Hop Identity Chain

Squad pods never hold credentials directly. Instead, identity flows through a 5-hop chain from the pod all the way to Microsoft Teams:

```
AKS Pod
  → Workload Identity (federated token projection)
    → Managed Identity / MSI + FIC (Azure AD)
      → Key Vault via CSI Driver (secret sync)
        → ROPC Token Exchange (delegated Graph token)
          → Graph API → Teams Message
```

### Hop 1: AKS Pod → Workload Identity

Each pod runs under a Kubernetes ServiceAccount annotated with a Managed Identity client ID. AKS projects a federated token into the pod at a well-known path. No credentials are stored — the token is generated at runtime by the AKS OIDC issuer.

```yaml
# ServiceAccount annotation
azure.workload.identity/client-id: "<your-msi-client-id>"
```

The pod label `azure.workload.identity/use: "true"` triggers the mutating webhook that injects:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_FEDERATED_TOKEN_FILE` (path to projected token)
- `AZURE_AUTHORITY_HOST`

### Hop 2: Workload Identity → Managed Identity (MSI + FIC)

**Managed Identity:** `msi-squad-agents`

A User-Assigned Managed Identity with a **Federated Identity Credential (FIC)** configured to trust the AKS cluster's OIDC issuer.

| FIC Field | Value |
|-----------|-------|
| Issuer | `https://oidc.prod-aks.azure.com/<your-aks-oidc-issuer-guid>/` |
| Subject | `system:serviceaccount:squad:squad-workload-sa` |
| Audience | `api://AzureADTokenExchange` |

This binding means: "When a pod running as `squad-workload-sa` in namespace `squad` presents a token, Azure AD accepts it as proof of identity for `msi-squad-agents`."

### Hop 3: MSI → Key Vault (CSI Driver)

**Key Vault:** `kv-squad-agents`

- Authentication: **Azure RBAC** (not access policies)
- MSI `msi-squad-agents` has role: **Key Vault Secrets User**

Secrets stored in Key Vault:

| Secret Name | Purpose |
|-------------|---------|
| `gh-token` | GitHub PAT for Copilot CLI / repo access |
| `dk8s-autobot-password` | Password for the bot account used in ROPC flow |

A `SecretProviderClass` resource instructs the Azure Key Vault CSI driver to sync these secrets into a Kubernetes Secret:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: squad-keyvault-sync
  namespace: squad
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "<your-msi-client-id>"
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-tenant-id>"
    objects: |
      array:
        - |
          objectName: gh-token
          objectType: secret
        - |
          objectName: dk8s-autobot-password
          objectType: secret
  secretObjects:
    - secretName: squad-kv-secrets
      type: Opaque
      data:
        - objectName: gh-token
          key: gh-token
        - objectName: dk8s-autobot-password
          key: dk8s-autobot-password
```

The CSI driver mounts as a volume in each pod. On mount, it:
1. Uses the pod's Workload Identity token to authenticate to Key Vault
2. Fetches the secrets
3. Creates/updates the Kubernetes Secret `squad-kv-secrets`

### Hop 4: ROPC Token Exchange

To send Teams messages, the pod needs a **delegated** Graph API token (app-only tokens can't send messages as a user). The Resource Owner Password Credential (ROPC) flow exchanges the bot account's credentials for a delegated token.

- **App ID:** `d3590ed6-52b3-4102-aeff-aad2292ab01c` (Microsoft Office well-known first-party app ID)
- **Username:** `<your-bot-upn>` (e.g., `dk8s-autobot@yourtenant.onmicrosoft.com`)
- **Password:** Retrieved from `squad-kv-secrets` → `dk8s-autobot-password`

Using a well-known first-party app ID avoids needing a custom app registration with admin-consented permissions.

See [Teams Messaging](teams-messaging.md) for the full ROPC flow and code examples.

### Hop 5: Graph API → Teams

With the delegated token, the pod calls:
```
POST https://graph.microsoft.com/v1.0/teams/{team-id}/channels/{channel-id}/messages
Authorization: Bearer <delegated-token>
```

Messages appear as sent by **"DK8S Bot"** (the bot account's display name).

## 3-Layer Security Model

| Layer | Mechanism | What It Protects |
|-------|-----------|-----------------|
| **Infrastructure** | Workload Identity + FIC | Pod → Azure identity binding. No credentials stored in cluster. |
| **Secret Storage** | Key Vault + CSI Driver | Secrets at rest. RBAC-scoped, audit-logged, rotatable without pod restart. |
| **Runtime** | ROPC + short-lived tokens | Delegated Graph access. Tokens are ephemeral, never persisted. |

## What's NOT in Kubernetes

This architecture ensures zero secrets are baked into the cluster:

| ❌ Not Here | ✅ Where It Lives |
|-------------|------------------|
| Passwords | Key Vault (`kv-squad-agents`) |
| API tokens | Key Vault → CSI → ephemeral K8s Secret |
| Tenant/Client IDs | ServiceAccount annotation + SecretProviderClass |
| Bot credentials | Key Vault → ROPC exchange → short-lived bearer token |
| Credentials in Docker images | Never. Images are credential-free. |
| Secrets in git | Never. Manifests use placeholders. |

## Flow Diagram (Text)

```
┌─────────────┐   projected    ┌───────────────────┐   FIC trust    ┌─────────────────┐
│  AKS Pod    │───  token  ───▶│  Workload Identity │──────────────▶│  MSI             │
│  (squad ns) │               │  (OIDC issuer)     │               │  msi-squad-agents│
└─────────────┘               └───────────────────┘               └────────┬────────┘
                                                                           │
                                                                    RBAC: Key Vault
                                                                    Secrets User
                                                                           │
                                                                           ▼
┌─────────────┐   ROPC         ┌───────────────────┐   CSI sync    ┌─────────────────┐
│  Graph API  │◀── bearer ────│  Azure AD          │◀─────────────│  Key Vault       │
│  (Teams)    │    token      │  token endpoint    │               │  kv-squad-agents │
└─────────────┘               └───────────────────┘               └─────────────────┘
```

## References

- [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Azure Key Vault CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [ROPC Flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth-ropc)
- [Graph API — Send Channel Message](https://learn.microsoft.com/en-us/graph/api/channel-post-messages)
