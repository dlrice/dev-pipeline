const path = require('path');
const fs = require('fs');
const { detect } = require('./detect');
const { generate } = require('./generate');

const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const NC = '\x1b[0m';

async function update() {
  const cwd = process.cwd();

  console.log('');
  console.log('  ==========================================');
  console.log('  Spec-Driven Pipeline — Update');
  console.log('  ==========================================');
  console.log('');

  // Check that pipeline.config.json exists
  const configPath = path.join(cwd, 'pipeline.config.json');
  if (!fs.existsSync(configPath)) {
    console.error('  Error: pipeline.config.json not found.');
    console.error('  Run "dev-pipeline init" first to set up the pipeline.');
    process.exit(1);
  }

  // Read existing config
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

  // Flatten config for generate (it expects the flat format from detect/prompt)
  const flatConfig = {
    framework: config.techStack?.framework,
    language: config.techStack?.language,
    styling: config.techStack?.styling,
    testRunner: config.techStack?.testRunner,
    e2eRunner: config.techStack?.e2eRunner,
    stateManagement: config.techStack?.stateManagement,
    packageManager: config.techStack?.packageManager || 'npm',
    commands: config.commands || {},
    customConventions: '',
    projectMaturity: 'established',
  };

  console.log('  Using existing pipeline.config.json');
  console.log(`  Tech stack: ${Object.values(config.techStack || {}).filter(Boolean).join(', ')}`);
  console.log('');
  console.log('  Updating scripts (preserving config, docs, specs, and reviews)...');
  console.log('');

  // Generate with force=false — only scripts get writeAlways treatment
  const { written, skipped } = generate(cwd, flatConfig, { force: false });

  if (written.length > 0) {
    console.log(`  ${GREEN}Updated:${NC}`);
    for (const f of written) {
      console.log(`    ${GREEN}✓${NC} ${f}`);
    }
  }

  if (skipped.length > 0) {
    console.log(`\n  ${YELLOW}Preserved (not modified):${NC}`);
    for (const f of skipped) {
      console.log(`    - ${f}`);
    }
  }

  console.log('');
  console.log('  Update complete. Scripts are now at the latest version.');
  console.log('  Your config, docs, specs, and reviews were preserved.');
  console.log('');
}

module.exports = { update };
