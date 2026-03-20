# Deploying Squad on AKS

## Cluster Sizing
- System pool: 1× Standard_B2s (2 vCPU, 4 GB) — coordinator + ralph
- Agent pool: 0-5× Standard_B2s spot — agents (scale with KEDA)

## Spot Instance Savings
- Standard_B2s: ~$30/month on-demand
- Spot pricing: ~$5-10/month (70-80% savings)
- Agents tolerate interruption (tasks are idempotent)

## Namespaces
- `squad-system`: coordinator, ralph, dashboard
- `squad-agents`: ephemeral agent pods
