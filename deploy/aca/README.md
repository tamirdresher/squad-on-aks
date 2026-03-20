# Deploying Squad on ACA (Azure Container Apps)

## Free Tier Limits
- 180,000 vCPU-seconds/month
- 360,000 GiB-seconds/month
- 2 million requests/month

## Estimated Usage
- Coordinator: ~1 vCPU, always-on ≈ 2.6M vCPU-seconds (exceeds free)
- **Optimization**: Use 0.25 vCPU ≈ 648K seconds (still over)
- **Better**: Scale to 0 when idle, use consumption plan

## Cost Optimization
Run coordinator + ralph on minimal resources (0.25 vCPU each).
At ~50% utilization: 2 × 0.25 × 0.5 × 2.6M ≈ 648K vCPU-seconds.
May need pay-as-you-go for always-on: ~$5-10/month.
