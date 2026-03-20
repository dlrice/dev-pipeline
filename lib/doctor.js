const { execSync } = require('child_process');

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const NC = '\x1b[0m';

async function doctor() {
  console.log('');
  console.log('  ==========================================');
  console.log('  Spec-Driven Pipeline — Doctor');
  console.log('  ==========================================');
  console.log('');

  let allGood = true;

  // Check Node.js
  allGood = check('Node.js', 'node --version', '18') && allGood;

  // Check Git
  allGood = check('Git', 'git --version') && allGood;

  // Check Claude Code
  allGood = check('Claude Code', 'claude --version') && allGood;

  // Check Gemini CLI
  allGood = check('Gemini CLI', 'gemini --version') && allGood;

  // Check Qwen Code
  allGood = check('Qwen Code', 'qwen --version') && allGood;

  // Check for pipeline files
  console.log('');
  console.log('  Pipeline files:');
  checkFile('pipeline.config.json');
  checkFile('CLAUDE.md');
  checkFile('GEMINI.md');
  checkFile('AGENTS.md');
  checkFile('CONTEXT.md');
  checkFile('scripts/dev-loop.sh');
  checkFile('scripts/setup.sh');
  checkFile('scripts/generate-context.sh');
  checkFile('specs/_template.md');

  console.log('');
  if (allGood) {
    console.log(`  ${GREEN}All tools installed.${NC} You're ready to go.`);
  } else {
    console.log(`  ${YELLOW}Some tools are missing.${NC} Run ./scripts/setup.sh to install them.`);
  }
  console.log('');
}

function check(name, command, minVersion) {
  try {
    const output = execSync(command, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
    const version = output.replace(/[^0-9.]/g, '').split('.')[0];

    if (minVersion && parseInt(version) < parseInt(minVersion)) {
      console.log(`  ${YELLOW}⚠${NC}  ${name}: ${output} (need v${minVersion}+)`);
      return false;
    }

    console.log(`  ${GREEN}✓${NC}  ${name}: ${output}`);
    return true;
  } catch (e) {
    console.log(`  ${RED}✗${NC}  ${name}: not found`);
    return false;
  }
}

function checkFile(filePath) {
  const fs = require('fs');
  if (fs.existsSync(filePath)) {
    console.log(`    ${GREEN}✓${NC} ${filePath}`);
  } else {
    console.log(`    ${RED}✗${NC} ${filePath} (missing)`);
  }
}

module.exports = { doctor };
