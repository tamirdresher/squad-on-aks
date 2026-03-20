# Work Routing Configuration

## Auto-Assignment Rules

### By Label
| Label | Agent | Notes |
|-------|-------|-------|
| `infra` | B'Elanna | AKS, ACA, networking |
| `security` | Worf | Secrets, auth, RBAC |
| `code` | Data | Application logic |
| `docs` | Seven | Documentation |
| `monitoring` | Ralph | Health, queues |

### By File Path
| Path Pattern | Agent |
|--------------|-------|
| `deploy/**` | B'Elanna |
| `src/**` | Data |
| `scripts/**` | B'Elanna |
| `docs/**` | Seven |
| `.squad/**` | Picard |

## Complexity Tiers

- 🟢 **Auto-merge**: Dependency updates, typo fixes, doc updates
- 🟡 **Review required**: New features, config changes, script changes
- 🔴 **Human required**: Architecture changes, security-sensitive, cost implications
