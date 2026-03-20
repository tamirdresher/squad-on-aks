# Key Vault Setup for Production

In production, use Azure Key Vault + CSI driver instead of plain K8s secrets.

## Prerequisites

1. AKS cluster with Workload Identity enabled
2. Key Vault CSI driver add-on installed
3. Managed Identity with Key Vault access

## Step 1: Create Key Vault

```bash
KV_NAME="squad-keyvault"
RG="squadrg"

az keyvault create \
  --name $KV_NAME \
  --resource-group $RG \
  --enable-rbac-authorization
```

## Step 2: Create Managed Identity

```bash
IDENTITY_NAME="squad-identity"

az identity create \
  --name $IDENTITY_NAME \
  --resource-group $RG

CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RG --query clientId -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
```

## Step 3: Grant Key Vault Access

```bash
KV_ID=$(az keyvault show --name $KV_NAME --resource-group $RG --query id -o tsv)

az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $CLIENT_ID \
  --scope $KV_ID
```

## Step 4: Store the GH_TOKEN

```bash
az keyvault secret set \
  --vault-name $KV_NAME \
  --name gh-token \
  --value "ghp_your_token_here"
```

## Step 5: Configure Workload Identity Federation

```bash
AKS_OIDC_ISSUER=$(az aks show --name squad-aks --resource-group $RG --query oidcIssuerProfile.issuerUrl -o tsv)

az identity federated-credential create \
  --name squad-federated-cred \
  --identity-name $IDENTITY_NAME \
  --resource-group $RG \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:squad:squad-agent-sa" \
  --audiences "api://AzureADTokenExchange"
```

## Step 6: Deploy with Key Vault Values

```bash
helm upgrade --install squad-agents helm/squad-agents \
  --set global.keyVaultName=$KV_NAME \
  --set global.tenantId=$TENANT_ID \
  --set global.identityClientId=$CLIENT_ID \
  --set serviceAccount.annotations."azure\.workload\.identity/client-id"=$CLIENT_ID
```

## How It Works

```
Pod → ServiceAccount (annotated) → Workload Identity → AAD Token
  → CSI Driver → Key Vault → Secret mounted as volume
```

No tokens stored in K8s secrets. No tokens in Helm values. Everything federated.
