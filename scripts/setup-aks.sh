#!/bin/bash
# Setup AKS cluster with spot instances for Squad
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-squad-aks-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-squad-aks}"
LOCATION="${LOCATION:-eastus}"

echo "🚀 Creating AKS cluster with spot instances..."

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# System node pool (small, always-on)
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --node-count 1 \
  --node-vm-size Standard_B2s \
  --generate-ssh-keys \
  --output none

# Spot node pool for agents (cheap, interruptible)
az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --name agents \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 5 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_B2s \
  --output none

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"

echo "✅ AKS cluster ready. Spot node pool: 0-5 agents"
echo "   Next: helm install squad ./deploy/helm/squad"
