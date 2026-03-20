# Architecture Decision Records

## ADR-001: Start with ACA Free Tier
**Date:** 2026-03-20
**Status:** Accepted
**Decision:** Start with Azure Container Apps free tier before scaling to AKS.
**Rationale:** ACA free tier provides 180K vCPU-seconds/month at zero cost, sufficient for initial deployment and validation. Migrating to AKS later is straightforward since both use containers.

## ADR-002: Ralph as Persistent Process
**Date:** 2026-03-20
**Status:** Accepted
**Decision:** Ralph runs as a persistent container (Deployment with 1 replica), not a CronJob.
**Rationale:** Continuous polling enables faster response to new issues. On AKS, we may switch to CronJob for cost optimization during off-hours.

## ADR-003: Agents as Ephemeral Containers
**Date:** 2026-03-20
**Status:** Accepted
**Decision:** Agent containers are spawned per-task and exit on completion.
**Rationale:** Keeps resource usage proportional to actual work. KEDA can scale agent count based on queue depth.
