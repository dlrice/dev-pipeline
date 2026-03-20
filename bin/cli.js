#!/usr/bin/env node

const command = process.argv[2];

const HELP = `
  spec-driven-pipeline — Multi-LLM development pipeline

  Usage:
    dev-pipeline init          Onboard the pipeline into the current repo
    dev-pipeline update        Update pipeline scripts (preserves config and docs)
    dev-pipeline doctor        Check that all tools are installed and authenticated
    dev-pipeline help          Show this help message

  Install into any repo:
    cd your-project
    npx github:YOUR-USERNAME/dev-pipeline init
`;

async function main() {
  switch (command) {
    case 'init':
      const { init } = require('../lib/init');
      await init();
      break;
    case 'update':
      const { update } = require('../lib/update');
      await update();
      break;
    case 'doctor':
      const { doctor } = require('../lib/doctor');
      await doctor();
      break;
    case 'help':
    case '--help':
    case '-h':
    case undefined:
      console.log(HELP);
      break;
    default:
      console.error(`Unknown command: ${command}`);
      console.log(HELP);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
