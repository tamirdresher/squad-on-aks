// Squad Ralph — work queue monitor
// Polls GitHub issues and ADO work items, pings coordinator when new work arrives
// TODO: Implement polling loop + coordinator notification

const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '60000');
const REPOS = (process.env.WATCHED_REPOS || '').split(',').filter(Boolean);

console.log(`[ralph] Starting work queue monitor`);
console.log(`[ralph] Poll interval: ${POLL_INTERVAL_MS}ms`);
console.log(`[ralph] Watching repos: ${REPOS.join(', ') || '(none configured)'}`);

async function pollForWork() {
  // TODO: Use Octokit to check for new issues with squad label
  console.log(`[ralph] Polling for new work items...`);
}

async function main() {
  while (true) {
    try {
      await pollForWork();
    } catch (err) {
      console.error(`[ralph] Error polling:`, err.message);
    }
    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
  }
}

main();
