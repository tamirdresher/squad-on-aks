# Squad Team — DevOps & K8s Focused

## Mission
Deploy and operate Squad AI agent teams on Azure Kubernetes Service and Azure Container Apps, enabling autonomous software engineering at cloud scale.

## Team Roster

| Agent | Role | Specialization |
|-------|------|----------------|
| **Picard** | Lead | Architecture, deployment strategy, orchestration decisions |
| **B'Elanna** | Infrastructure | AKS, Helm, ACA, container networking, KEDA |
| **Worf** | Security & Cloud | Azure Key Vault, managed identity, RBAC, network policies |
| **Data** | Code Expert | Coordinator logic, agent base image, Node.js containers |
| **Seven** | Research & Docs | Documentation, cost analysis, architecture diagrams |
| **Ralph** | Work Monitor | ADO/GitHub queue watching, keep-alive, health checks |

## Routing Rules

- **Infrastructure issues** (AKS, ACA, Helm, networking) → B'Elanna
- **Security issues** (secrets, auth, RBAC) → Worf
- **Code changes** (coordinator, ralph, agent logic) → Data
- **Documentation** (README, architecture, cost analysis) → Seven
- **Work queue / monitoring** → Ralph
- **Architecture decisions** → Picard (always reviews)

## Labels

- `squad` — eligible for agent processing
- `squad:copilot` — assigned to Copilot agent
- `phase-1` — Free tier (ACA)
- `phase-2` — AKS scale-out
- `phase-3` — Production hardening
