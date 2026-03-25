export default {
  version: '1.0.0',
  models: {
    defaultModel: 'claude-sonnet-4.5',
    defaultTier: 'standard',
    fallbackChains: {
      premium: ['claude-opus-4.6', 'claude-sonnet-4.5'],
      standard: ['claude-sonnet-4.5', 'gpt-5.2-codex', 'claude-sonnet-4'],
      fast: ['claude-haiku-4.5', 'gpt-4.1'],
    },
    preferSameProvider: true,
    respectTierCeiling: true,
    nuclearFallback: { enabled: false },
  },
  routing: {
    rules: {
      'feature-dev': { agent: '@scribe' },
      'bug-fix': { agent: '@scribe' },
      'testing': { agent: '@scribe' },
      'documentation': { agent: '@scribe' },
    },
    governance: {
      eagerByDefault: true,
      scribeAutoRuns: false,
      allowRecursiveSpawn: false,
    },
  },
  platforms: {
    vscode: {
      disableModelSelection: false,
      scribeMode: 'sync',
    },
  },
} as const;
