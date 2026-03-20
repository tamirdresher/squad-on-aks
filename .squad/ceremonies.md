# Squad Ceremonies

## Daily Standup (Async)

**Frequency:** Every CronJob cycle (default: every 5 minutes)
**Owner:** Ralph (Work Monitor)
**Format:** Async — Ralph scans the GitHub issue board and reports status

**Process:**
1. Ralph polls the issue queue for items labeled `squad:*`
2. New issues are triaged and routed per `.squad/routing.md`
3. In-progress items are checked for staleness (no update in 24h → ping assignee)
4. Completed PRs are verified and issues closed

**Output:** Ralph logs activity to pod stdout (visible via `kubectl logs`)

## PR Review Process

**Turnaround target:** < 1 hour for squad-generated PRs

**Process:**
1. Agent opens PR with `squad:review` label
2. Picard (Lead) reviews architecture and design decisions
3. Domain expert reviews implementation:
   - Infrastructure changes → B'Elanna
   - Security changes → Worf
   - Code/logic changes → Data
   - Documentation → Seven
4. Minimum 1 approval required before merge
5. CI checks must pass (lint, build, test)

**Auto-merge criteria:**
- Documentation-only changes with passing CI
- Dependency updates with passing CI and no breaking changes

## Decision Log Protocol

**Location:** `.squad/decisions.md`

**When to log:**
- Architecture decisions (ADRs)
- Technology choices
- Security policy changes
- Process changes

**Format:**
```markdown
### DECISION-NNN: [Title]
**Date:** YYYY-MM-DD
**Decision maker:** [Agent name]
**Status:** Accepted | Superseded | Deprecated

**Context:** Why was this decision needed?
**Decision:** What was decided?
**Consequences:** What are the implications?
```

**Review:** Picard reviews all decisions. Security-related decisions require Worf sign-off.
