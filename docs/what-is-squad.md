# What is Squad?

**Squad** is an AI team framework where specialized agents collaborate on software projects through GitHub issues.

## The Team

Each Squad has agents with distinct roles:

| Role | Agent | What They Do |
|------|-------|-------------|
| **Lead** | Picard | Architecture decisions, code review, coordination |
| **Monitor** | Ralph | Polls GitHub issues, dispatches work, keeps things moving |
| **Specialist** | (varies) | Frontend, Backend, Security, Infrastructure, etc. |
| **Scribe** | Scribe | Maintains decisions log, cross-agent context sharing |

## How It Works

1. **Issues arrive** in GitHub (created by humans or automated)
2. **Ralph** (work monitor) polls every 5 minutes, finds new/unassigned issues
3. Ralph **routes** the issue to the right specialist agent based on labels
4. The specialist **works** the issue (writes code, creates PRs, runs tests)
5. **Picard** reviews the work and approves/requests changes
6. Humans review the final PR and merge

## Why Kubernetes?

Running Squad on AKS gives you:

- **Cost efficiency** — Ralph runs as a CronJob (no always-on pod), agents spin up only when there's work
- **Scale** — KEDA can scale from zero to many agent pods based on workload
- **Security** — Workload Identity + Key Vault means no tokens in your cluster
- **Reliability** — K8s handles restarts, health checks, and scheduling
- **Multi-repo** — One cluster can run Ralph for multiple repositories

## Squad vs. Single Agent

| Aspect | Single Agent | Squad |
|--------|-------------|-------|
| Context | One agent tries to know everything | Specialists with focused knowledge |
| Parallelism | Sequential | Multiple agents work simultaneously |
| Quality | No review | Picard reviews all work |
| Memory | Session-only | Persistent via `.squad/decisions.md` |
| Scaling | One machine | K8s horizontal scaling |

## Learn More

- [GitHub: tamirdresher/squad](https://github.com/tamirdresher/tamresearch1) — Original Squad implementation
- [Deployment Timeline](deployment-timeline.md) — Real deployment story
- [KEDA Scaling](keda-scaling.md) — Autoscaling strategies
