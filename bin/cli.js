#!/usr/bin/env node

const command = process.argv[2];
const args = process.argv.slice(3);

const HELP = `
  aidev — Multi-LLM spec-driven development pipeline

  Usage:
    aidev init                 Set up aidev in the current repo (creates aidev.config.json)
    aidev run <feature>        Run the pipeline for a feature spec
    aidev doctor               Check that all tools are installed and authenticated
    aidev setup                Install CLI agents (Claude Code, Gemini CLI, Qwen Code)
    aidev help                 Show this help message

  Pipeline flags (for 'run'):
    --from N                   Start from phase N
    --only N                   Run only phase N
    --force                    Skip complexity halts
    --reset                    Clear state and start over

  Quick start:
    aidev init
    aidev setup
    cp aidev/specs/_template.md aidev/specs/my-feature.md
    # Edit the spec...
    aidev run my-feature
`;

async function main() {
  switch (command) {
    case 'init': {
      const { init } = require('../lib/init');
      await init();
      break;
    }
    case 'run': {
      const feature = args[0];
      if (!feature) {
        console.error('  Error: feature name required.');
        console.error('  Usage: aidev run <feature-name>');
        process.exit(1);
      }
      const { run } = require('../lib/run');
      await run(feature, args.slice(1));
      break;
    }
    case 'doctor': {
      const { doctor } = require('../lib/doctor');
      await doctor();
      break;
    }
    case 'setup': {
      const { setup } = require('../lib/setup');
      await setup();
      break;
    }
    case 'help':
    case '--help':
    case '-h':
    case undefined:
      console.log(HELP);
      break;
    default:
      console.error(`  Unknown command: ${command}`);
      console.log(HELP);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
