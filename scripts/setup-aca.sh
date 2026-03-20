#!/bin/bash
# Setup Azure Container Apps free tier environment
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-squad-aca-rg}"
LOCATION="${LOCATION:-eastus}"
ACA_ENV="${ACA_ENV:-squad-env}"

echo "🚀 Setting up ACA free tier environment..."

# Create resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
echo "✅ Resource group: $RESOURCE_GROUP"

# Create ACA environment
az containerapp env create \
  --name "$ACA_ENV" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
echo "✅ ACA environment: $ACA_ENV"

echo ""
echo "🎉 ACA environment ready! Next: ./scripts/deploy-aca.sh"
