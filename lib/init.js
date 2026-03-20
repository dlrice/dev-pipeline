const path = require('path');
const { detect } = require('./detect');
const { confirmDetection } = require('./prompt');
const { generate } = require('./generate');

const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const NC = '\x1b[0m';

async function init() {
  const cwd = process.cwd();

  console.log('');
  console.log('  ==========================================');
  console.log('  Spec-Driven Pipeline — Init');
  console.log('  ==========================================');
  console.log('');

  // Step 1: Detect
  console.log('  Scanning project...');
  const detected = detect(cwd);

  // Warn about existing files
  if (detected.existingFiles.length > 0) {
    console.log(`\n  ${YELLOW}!${NC} Found existing pipeline files:`);
    for (const f of detected.existingFiles) {
      console.log(`    - ${f}`);
    }
    console.log('  These will NOT be overwritten. Use --force to replace them.');
    console.log('  Scripts (scripts/*.sh) are always updated to the latest version.');
    console.log('');
  }

  // Step 2: Confirm and ask
  const config = await confirmDetection(detected);

  // Step 3: Generate
  console.log('\n  Writing pipeline files...\n');
  const force = process.argv.includes('--force');
  const { written, skipped } = generate(cwd, config, { force });

  // Report
  if (written.length > 0) {
    console.log(`  ${GREEN}Created/updated:${NC}`);
    for (const f of written) {
      console.log(`    ${GREEN}✓${NC} ${f}`);
    }
  }

  if (skipped.length > 0) {
    console.log(`\n  ${YELLOW}Skipped (already exist):${NC}`);
    for (const f of skipped) {
      console.log(`    - ${f}`);
    }
  }

  // Next steps
  console.log('');
  console.log('  ==========================================');
  console.log('  Setup complete!');
  console.log('  ==========================================');
  console.log('');
  console.log('  Next steps:');
  console.log('');
  console.log('  1. Install CLI tools:');
  console.log(`     ${GREEN}./scripts/setup.sh${NC}`);
  console.log('');
  console.log('  2. Authenticate each tool once:');
  console.log(`     ${GREEN}claude${NC}   — sign in with Claude Pro account`);
  console.log(`     ${GREEN}gemini${NC}   — sign in with Google account`);
  console.log(`     ${GREEN}qwen${NC}     — sign in with Qwen account (qwen.ai)`);
  console.log('');

  if (config.runBootstrap) {
    console.log('  3. Bootstrap docs from your codebase:');
    console.log(`     ${GREEN}./scripts/setup.sh --bootstrap${NC}`);
    console.log('');
    console.log('  4. Generate initial context file:');
    console.log(`     ${GREEN}./scripts/generate-context.sh${NC}`);
  } else {
    console.log('  3. Generate initial context file:');
    console.log(`     ${GREEN}./scripts/generate-context.sh${NC}`);
  }

  console.log('');
  console.log('  5. Start building:');
  console.log(`     cp specs/_template.md specs/my-feature.md`);
  console.log(`     # Edit the spec`);
  console.log(`     ${GREEN}./scripts/dev-loop.sh my-feature${NC}`);
  console.log('');
}

module.exports = { init };
