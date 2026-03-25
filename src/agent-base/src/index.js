// Squad Agent Base — processes a single GitHub issue then exits
// Clones the repo, creates a branch, and leaves a placeholder commit

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { Octokit } = require('@octokit/rest');

const AGENT_TYPE = process.env.AGENT_TYPE || 'generic';
const ISSUE_URL = process.env.ISSUE_URL || '';
const ISSUE_NUMBER = process.env.ISSUE_NUMBER;
const REPO = process.env.REPO || '';
const ISSUE_TITLE = process.env.ISSUE_TITLE || '';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const WORK_DIR = process.env.WORK_DIR || '/workspace';

function ts() {
  return new Date().toISOString();
}

function log(msg) {
  console.log(`[${ts()}] [agent:${AGENT_TYPE}] ${msg}`);
}

function logError(msg, err) {
  console.error(`[${ts()}] [agent:${AGENT_TYPE}] ${msg}`, err?.message || err);
}

function run(cmd, opts = {}) {
  log(`$ ${cmd}`);
  return execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...opts });
}

async function processTask() {
  log(`Starting task for issue #${ISSUE_NUMBER}: "${ISSUE_TITLE}"`);
  log(`Repo: ${REPO}`);
  log(`Issue URL: ${ISSUE_URL}`);

  if (!REPO || !ISSUE_NUMBER) {
    throw new Error('REPO and ISSUE_NUMBER env vars are required');
  }

  if (!GITHUB_TOKEN) {
    throw new Error('GITHUB_TOKEN env var is required');
  }

  const [owner, repoName] = REPO.split('/');
  if (!owner || !repoName) {
    throw new Error(`Invalid REPO format "${REPO}" — expected owner/repo`);
  }

  const octokit = new Octokit({ auth: GITHUB_TOKEN });
  const branchName = `squad/issue-${ISSUE_NUMBER}`;
  const cloneDir = path.join(WORK_DIR, repoName);

  // Ensure work directory exists
  fs.mkdirSync(WORK_DIR, { recursive: true });

  // Clone the repo
  const cloneUrl = `https://x-access-token:${GITHUB_TOKEN}@github.com/${owner}/${repoName}.git`;
  log(`Cloning ${owner}/${repoName}...`);
  run(`git clone --depth 1 "${cloneUrl}" "${cloneDir}"`);

  // Create and checkout branch
  log(`Creating branch ${branchName}`);
  run(`git checkout -b "${branchName}"`, { cwd: cloneDir });

  // Configure git identity
  run('git config user.email "squad-agent@squad-on-aks.dev"', { cwd: cloneDir });
  run('git config user.name "Squad Agent"', { cwd: cloneDir });

  // Create a placeholder file showing the agent was dispatched
  const dispatchFile = path.join(cloneDir, '.squad', `issue-${ISSUE_NUMBER}.md`);
  fs.mkdirSync(path.dirname(dispatchFile), { recursive: true });
  fs.writeFileSync(dispatchFile, [
    `# Squad Agent Dispatch — Issue #${ISSUE_NUMBER}`,
    '',
    `- **Issue:** ${ISSUE_TITLE}`,
    `- **URL:** ${ISSUE_URL}`,
    `- **Agent type:** ${AGENT_TYPE}`,
    `- **Dispatched at:** ${ts()}`,
    '',
    '> This file was created by the Squad agent to confirm dispatch.',
    '> The agent will process this issue and update the branch with changes.',
    '',
  ].join('\n'));

  // Commit the placeholder
  run('git add -A', { cwd: cloneDir });
  run(`git commit -m "squad: dispatch agent for issue #${ISSUE_NUMBER}"`, { cwd: cloneDir });

  // Attempt to push the branch
  try {
    run(`git push origin "${branchName}"`, { cwd: cloneDir });
    log(`Pushed branch ${branchName}`);
  } catch (err) {
    logError('Failed to push branch (may need write permissions):', err);
  }

  // Comment on the issue that the agent has been dispatched
  try {
    await octokit.issues.createComment({
      owner,
      repo: repoName,
      issue_number: parseInt(ISSUE_NUMBER, 10),
      body: `🤖 Squad agent (\`${AGENT_TYPE}\`) dispatched on branch \`${branchName}\`.`,
    });
    log('Commented on issue with dispatch status');
  } catch (err) {
    logError('Failed to comment on issue:', err);
  }

  log('Task processing complete');
}

processTask()
  .then(() => {
    log('Exiting successfully');
    process.exit(0);
  })
  .catch(err => {
    logError('Task failed:', err);
    process.exit(1);
  });
