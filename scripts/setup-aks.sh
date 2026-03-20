#!/bin/bash
# setup-aks.sh — Create AKS cluster + ACR for Squad
# Usage: ./scripts/setup-aks.sh <resource-group> <location>
#
# Prerequisites: az CLI logged in, sufficient subscription quota

set -euo pipefail

RG="${1:-squadrg}"
LOCATION="${2:-eastus}"
CLUSTER_NAME="squad-aks"
ACR_NAME="squadacr$(openssl rand -hex 3)"  # Globally unique

echo "=== Squad AKS Setup ==="
echo "Resource Group: $RG"
echo "Location:       $LOCATION"
echo "Cluster:        $CLUSTER_NAME"
echo "ACR:            $ACR_NAME"
echo ""

# --- Resource Group ---
echo "Creating resource group..."
az group create --name "$RG" --location "$LOCATION" --output none

# --- ACR ---
echo "Creating Azure Container Registry..."
az acr create \
  --resource-group "$RG" \
  --name "$ACR_NAME" \
  --sku Basic \
  --location "$LOCATION" \
  --output none

echo "  ✅ ACR: ${ACR_NAME}.azurecr.io"

# --- AKS ---
echo "Creating AKS cluster (this takes ~5-10 minutes)..."
az aks create \
  --resource-group "$RG" \
  --name "$CLUSTER_NAME" \
  --node-count 1 \
  --node-vm-size Standard_D2s_v3 \
  --generate-ssh-keys \
  --enable-managed-identity \
  --attach-acr "$ACR_NAME" \
  --output none

echo "  ✅ AKS: $CLUSTER_NAME"

# --- Get credentials ---
echo "Getting cluster credentials..."
az aks get-credentials \
  --resource-group "$RG" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Build the Docker image:"
echo "     az acr build --registry $ACR_NAME --image squad-ralph:latest docker/"
echo ""
echo "  2. Create the GH_TOKEN secret:"
echo "     kubectl create namespace squad"
echo "     kubectl create secret generic squad-runtime-secrets \\"
echo "       --namespace squad --from-literal=GH_TOKEN=ghp_your_token"
echo ""
echo "  3. Deploy with Helm:"
echo "     helm upgrade --install squad-agents helm/squad-agents \\"
echo "       --set global.acrLoginServer=${ACR_NAME}.azurecr.io \\"
echo "       --set global.repository=your-org/your-repo \\"
echo "       --create-namespace --namespace squad"
