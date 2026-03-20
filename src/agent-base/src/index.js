// Squad Agent Base — processes a single task then exits
// Specialized agents override AGENT_TYPE and task processing logic
// TODO: Implement task processing pipeline

const AGENT_TYPE = process.env.AGENT_TYPE || 'generic';
const TASK_ID = process.env.TASK_ID;

console.log(`[agent:${AGENT_TYPE}] Starting task ${TASK_ID || '(none)'}`);

async function processTask() {
  // TODO: Clone repo, run Copilot CLI, create PR
  console.log(`[agent:${AGENT_TYPE}] Processing task...`);
}

processTask()
  .then(() => {
    console.log(`[agent:${AGENT_TYPE}] Task complete`);
    process.exit(0);
  })
  .catch(err => {
    console.error(`[agent:${AGENT_TYPE}] Task failed:`, err.message);
    process.exit(1);
  });
