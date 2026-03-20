#!/bin/bash
# Deploy Squad containers to Azure Container Apps
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-squad-aca-rg}"
ACA_ENV="${ACA_ENV:-squad-env}"
REGISTRY="${REGISTRY:-squadonaks.azurecr.io}"

echo "📦 Building containers..."

docker build -t "$REGISTRY/squad-coordinator:latest" ./src/coordinator/
docker build -t "$REGISTRY/squad-ralph:latest" ./src/ralph/
docker build -t "$REGISTRY/squad-agent-base:latest" ./src/agent-base/

echo "🚀 Deploying to ACA..."

# Deploy coordinator
az containerapp create \
  --name squad-coordinator \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ACA_ENV" \
  --image "$REGISTRY/squad-coordinator:latest" \
  --target-port 3000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1 \
  --env-vars "GITHUB_TOKEN=secretref:github-token" \
  --output none

# Deploy Ralph (persistent, no ingress)
az containerapp create \
  --name squad-ralph \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ACA_ENV" \
  --image "$REGISTRY/squad-ralph:latest" \
  --min-replicas 1 \
  --max-replicas 1 \
  --env-vars "GITHUB_TOKEN=secretref:github-token WATCHED_REPOS=your-org/squad-on-aks" \
  --output none

echo "✅ Deployed! Coordinator URL:"
az containerapp show --name squad-coordinator --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv
