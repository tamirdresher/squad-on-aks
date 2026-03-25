// Squad Ralph — work queue monitor
// Polls GitHub issues for the `squad` label and notifies the coordinator

const http = require('http');
const { Octokit } = require('@octokit/rest');

const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '60000', 10);
const REPOS = (process.env.WATCHED_REPOS || '').split(',').map(r => r.trim()).filter(Boolean);
const COORDINATOR_URL = process.env.COORDINATOR_URL || 'http://coordinator:3000';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const HEALTH_PORT = parseInt(process.env.HEALTH_PORT || '3001', 10);

// Issues we already reported — keyed by issue HTML URL
const reportedIssues = new Set();

function ts() {
  return new Date().toISOString();
}

function log(msg) {
  console.log(`[${ts()}] [ralph] ${msg}`);
}

function logError(msg, err) {
  console.error(`[${ts()}] [ralph] ${msg}`, err?.message || err);
}

function createOctokit() {
  if (!GITHUB_TOKEN) {
    throw new Error('GITHUB_TOKEN env var is required');
  }
  return new Octokit({ auth: GITHUB_TOKEN });
}

// POST issue details to the coordinator webhook
async function notifyCoordinator(issue, repo) {
  const payload = JSON.stringify({
    issue_url: issue.html_url,
    issue_number: issue.number,
    repo,
    title: issue.title,
    labels: issue.labels.map(l => l.name),
    created_at: issue.created_at,
  });

  const url = new URL('/webhook', COORDINATOR_URL);

  return new Promise((resolve, reject) => {
    const proto = url.protocol === 'https:' ? require('https') : http;
    const req = proto.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(body);
        } else {
          reject(new Error(`Coordinator responded ${res.statusCode}: ${body}`));
        }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function pollForWork(octokit) {
  log(`Polling ${REPOS.length} repo(s) for issues labeled "squad"...`);

  for (const repo of REPOS) {
    const [owner, name] = repo.split('/');
    if (!owner || !name) {
      logError(`Invalid repo format "${repo}" — expected owner/repo`);
      continue;
    }

    try {
      const { data: issues } = await octokit.issues.listForRepo({
        owner,
        repo: name,
        labels: 'squad',
        state: 'open',
        per_page: 50,
        assignee: 'none',
      });

      log(`  ${owner}/${name}: found ${issues.length} open unassigned squad issue(s)`);

      for (const issue of issues) {
        // Skip pull requests (GitHub returns them in the issues endpoint)
        if (issue.pull_request) continue;

        if (reportedIssues.has(issue.html_url)) {
          continue;
        }

        log(`  → New issue #${issue.number}: "${issue.title}" — notifying coordinator`);
        try {
          await notifyCoordinator(issue, repo);
          reportedIssues.add(issue.html_url);
          log(`  ✓ Coordinator notified for #${issue.number}`);
        } catch (err) {
          logError(`  ✗ Failed to notify coordinator for #${issue.number}:`, err);
        }
      }
    } catch (err) {
      logError(`  ✗ Error fetching issues from ${repo}:`, err);
    }
  }
}

// Health endpoint for K8s liveness probes
function startHealthServer() {
  const healthServer = http.createServer((req, res) => {
    if (req.url === '/health' || req.url === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'healthy',
        role: 'ralph',
        uptime: process.uptime(),
        reportedCount: reportedIssues.size,
        watchedRepos: REPOS,
      }));
      return;
    }
    res.writeHead(404);
    res.end('Not found');
  });

  healthServer.listen(HEALTH_PORT, () => {
    log(`Health endpoint listening on port ${HEALTH_PORT}`);
  });

  return healthServer;
}

async function main() {
  log('Starting work queue monitor');
  log(`Poll interval: ${POLL_INTERVAL_MS}ms`);
  log(`Coordinator URL: ${COORDINATOR_URL}`);
  log(`Watching repos: ${REPOS.join(', ') || '(none configured)'}`);

  if (!GITHUB_TOKEN) {
    logError('GITHUB_TOKEN is not set — cannot poll GitHub. Exiting.');
    process.exit(1);
  }

  if (REPOS.length === 0) {
    logError('WATCHED_REPOS is empty — nothing to watch. Exiting.');
    process.exit(1);
  }

  const octokit = createOctokit();
  startHealthServer();

  // Poll loop
  while (true) {
    try {
      await pollForWork(octokit);
    } catch (err) {
      logError('Unexpected error during poll cycle:', err);
    }
    await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
  }
}

// Graceful shutdown
process.on('SIGTERM', () => {
  log('Received SIGTERM — shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  log('Received SIGINT — shutting down');
  process.exit(0);
});

main();
