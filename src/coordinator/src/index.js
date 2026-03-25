// Squad Coordinator — routes GitHub issues to agent containers
// Accepts work from Ralph, processes issues via the GitHub API

const http = require('http');
const { Octokit } = require('@octokit/rest');

const PORT = parseInt(process.env.PORT || '3000', 10);
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const AGENT_GITHUB_USER = process.env.AGENT_GITHUB_USER || '';
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT || '5', 10);

// Work queue: each item has { id, issue_url, issue_number, repo, title, status, queued_at, started_at, finished_at, error }
const workQueue = [];
let activeCount = 0;

function ts() {
  return new Date().toISOString();
}

function log(msg) {
  console.log(`[${ts()}] [coordinator] ${msg}`);
}

function logError(msg, err) {
  console.error(`[${ts()}] [coordinator] ${msg}`, err?.message || err);
}

function createOctokit() {
  if (!GITHUB_TOKEN) {
    throw new Error('GITHUB_TOKEN env var is required');
  }
  return new Octokit({ auth: GITHUB_TOKEN });
}

// Read full request body as a string
function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

// Process a single queued issue
async function processItem(item, octokit) {
  const [owner, repo] = item.repo.split('/');
  if (!owner || !repo) {
    throw new Error(`Invalid repo format: ${item.repo}`);
  }

  log(`Processing issue #${item.issue_number} in ${item.repo}`);

  // Add squad-in-progress label
  try {
    await octokit.issues.addLabels({
      owner,
      repo,
      issue_number: item.issue_number,
      labels: ['squad-in-progress'],
    });
    log(`  ✓ Added "squad-in-progress" label to #${item.issue_number}`);
  } catch (err) {
    logError(`  ✗ Failed to add label to #${item.issue_number}:`, err);
  }

  // Assign to agent user if configured
  if (AGENT_GITHUB_USER) {
    try {
      await octokit.issues.addAssignees({
        owner,
        repo,
        issue_number: item.issue_number,
        assignees: [AGENT_GITHUB_USER],
      });
      log(`  ✓ Assigned #${item.issue_number} to ${AGENT_GITHUB_USER}`);
    } catch (err) {
      logError(`  ✗ Failed to assign #${item.issue_number}:`, err);
    }
  }

  // Comment on the issue
  try {
    await octokit.issues.createComment({
      owner,
      repo,
      issue_number: item.issue_number,
      body: '🤖 Squad coordinator picked up this issue. Agent dispatching...',
    });
    log(`  ✓ Commented on #${item.issue_number}`);
  } catch (err) {
    logError(`  ✗ Failed to comment on #${item.issue_number}:`, err);
  }
}

// Drain the queue up to MAX_CONCURRENT active
async function drainQueue(octokit) {
  while (activeCount < MAX_CONCURRENT) {
    const next = workQueue.find(item => item.status === 'pending');
    if (!next) break;

    next.status = 'in-progress';
    next.started_at = ts();
    activeCount++;

    // Process async — don't block the queue
    processItem(next, octokit)
      .then(() => {
        next.status = 'done';
        next.finished_at = ts();
        log(`Issue #${next.issue_number} processing complete`);
      })
      .catch((err) => {
        next.status = 'error';
        next.error = err.message;
        next.finished_at = ts();
        logError(`Issue #${next.issue_number} processing failed:`, err);
      })
      .finally(() => {
        activeCount--;
        // Try to drain more items
        drainQueue(octokit).catch(err => logError('Queue drain error:', err));
      });
  }
}

function handleHealth(req, res) {
  const pending = workQueue.filter(i => i.status === 'pending').length;
  const inProgress = workQueue.filter(i => i.status === 'in-progress').length;
  const done = workQueue.filter(i => i.status === 'done').length;
  const errors = workQueue.filter(i => i.status === 'error').length;

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'healthy',
    role: 'coordinator',
    uptime: process.uptime(),
    queue: { pending, inProgress, done, errors, total: workQueue.length },
    maxConcurrent: MAX_CONCURRENT,
  }));
}

function handleWebhook(req, res, octokit) {
  readBody(req)
    .then(body => {
      let payload;
      try {
        payload = JSON.parse(body);
      } catch {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
        return;
      }

      const { issue_url, issue_number, repo, title } = payload;
      if (!issue_number || !repo) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Missing required fields: issue_number, repo' }));
        return;
      }

      // Deduplicate by issue URL
      const existing = workQueue.find(i => i.issue_url === issue_url);
      if (existing) {
        log(`Issue #${issue_number} already in queue (status: ${existing.status})`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ queued: false, reason: 'duplicate', status: existing.status }));
        return;
      }

      const item = {
        id: `work-${Date.now()}-${issue_number}`,
        issue_url: issue_url || '',
        issue_number,
        repo,
        title: title || '',
        status: 'pending',
        queued_at: ts(),
        started_at: null,
        finished_at: null,
        error: null,
      };

      workQueue.push(item);
      log(`Queued issue #${issue_number}: "${title}" from ${repo}`);

      // Kick off processing
      drainQueue(octokit).catch(err => logError('Queue drain error:', err));

      res.writeHead(201, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ queued: true, id: item.id }));
    })
    .catch(err => {
      logError('Error reading webhook body:', err);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Internal server error' }));
    });
}

function handleStatus(req, res) {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    queue: workQueue.map(({ id, issue_number, repo, title, status, queued_at, started_at, finished_at, error }) => ({
      id, issue_number, repo, title, status, queued_at, started_at, finished_at, error,
    })),
    activeCount,
    maxConcurrent: MAX_CONCURRENT,
  }));
}

function main() {
  log('Starting Squad Coordinator');
  log(`Max concurrent agents: ${MAX_CONCURRENT}`);
  log(`Agent GitHub user: ${AGENT_GITHUB_USER || '(not configured — will comment only)'}`);

  if (!GITHUB_TOKEN) {
    logError('GITHUB_TOKEN is not set — issue processing will fail');
  }

  let octokit = null;
  if (GITHUB_TOKEN) {
    octokit = createOctokit();
  }

  const server = http.createServer((req, res) => {
    // Simple path routing (ignore query strings)
    const path = req.url.split('?')[0];

    if (path === '/health' || path === '/healthz') {
      handleHealth(req, res);
      return;
    }

    if (path === '/webhook' && req.method === 'POST') {
      if (!octokit) {
        res.writeHead(503, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'GITHUB_TOKEN not configured' }));
        return;
      }
      handleWebhook(req, res, octokit);
      return;
    }

    if (path === '/status') {
      handleStatus(req, res);
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  });

  server.listen(PORT, () => {
    log(`Listening on port ${PORT}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    log('Received SIGTERM — shutting down gracefully');
    server.close(() => process.exit(0));
  });

  process.on('SIGINT', () => {
    log('Received SIGINT — shutting down');
    server.close(() => process.exit(0));
  });
}

main();
