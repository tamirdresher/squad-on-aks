# GitHub Actions CI/CD Setup

> How to configure the `deploy.yml` workflow to build and deploy Squad agents to AKS.

## Prerequisites

- Azure CLI (`az`) installed
- Owner/admin access to the GitHub repo
- An AKS cluster with ACR attached (see main README)

## Step 1: Create an Azure AD App Registration

```bash
APP_NAME="squad-on-aks-github"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP="your-resource-group"

# Create the app registration
az ad app create --display-name $APP_NAME
APP_ID=$(az ad app list --display-name $APP_NAME --query "[0].appId" -o tsv)

# Create a service principal
az ad sp create --id $APP_ID
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Grant Contributor on the resource group (AKS + ACR)
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP
```

## Step 2: Configure OIDC Federation (Recommended)

OIDC federation means no secrets to rotate — GitHub Actions gets short-lived tokens.

```bash
# Get your GitHub org/repo info
GITHUB_ORG="your-org"
GITHUB_REPO="squad-on-aks"

# Create federated credential for the main branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG/$GITHUB_REPO':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Step 3: Add GitHub Secrets

Go to your repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret Name | Value | How to Get It |
|------------|-------|---------------|
| `AZURE_CLIENT_ID` | App registration Application (client) ID | `az ad app list --display-name $APP_NAME --query "[0].appId" -o tsv` |
| `AZURE_TENANT_ID` | Azure AD tenant ID | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `az account show --query id -o tsv` |

## Step 4: Update deploy.yml (if needed)

The default `deploy.yml` expects these environment variables — update them for your setup:

```yaml
env:
  ACR_NAME: yourregistry        # Your ACR name (without .azurecr.io)
  AKS_CLUSTER: squad-aks        # Your AKS cluster name
  RESOURCE_GROUP: your-rg        # Your resource group
```

## Step 5: Test

Push a change to `docker/`, `helm/`, or `scripts/` on main — or use workflow_dispatch:

```bash
gh workflow run deploy.yml
```

## Alternative: Client Secret (Simpler, Less Secure)

If OIDC doesn't work in your environment:

```bash
# Create a client secret
az ad app credential reset --id $APP_ID --append

# Add as GitHub secret
# AZURE_CREDENTIALS = the full JSON output from the above command
```

Then update `deploy.yml` to use `creds: ${{ secrets.AZURE_CREDENTIALS }}` instead of OIDC.
