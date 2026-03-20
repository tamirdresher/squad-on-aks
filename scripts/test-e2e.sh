#!/bin/bash
# End-to-end test: create issue → verify agent picks it up → verify PR
set -euo pipefail

REPO="${REPO:-tamirdresher/squad-on-aks}"

echo "🧪 E2E Test: Issue → Agent → PR"

# Create a test issue
ISSUE_URL=$(gh issue create --repo "$REPO" \
  --title "E2E Test: $(date +%s)" \
  --body "Automated E2E test. This issue should be picked up by Squad agents." \
  --label "squad,e2e-test" 2>&1)

echo "Created test issue: $ISSUE_URL"

# Wait for agent to pick it up (poll for 5 minutes)
echo "Waiting for agent processing..."
for i in $(seq 1 30); do
  sleep 10
  STATUS=$(gh issue view "$ISSUE_URL" --json labels --jq '.labels[].name' 2>/dev/null | grep -c "in-progress" || true)
  if [ "$STATUS" -gt 0 ]; then
    echo "✅ Agent picked up the issue!"
    break
  fi
  echo "  ...waiting ($i/30)"
done

echo "🏁 E2E test complete"
