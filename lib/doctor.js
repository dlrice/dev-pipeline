const { execSync } = require('child_process');
const fs = require('fs');

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const BOLD = '\x1b[1m';
const NC = '\x1b[0m';

async function doctor() {
  console.log('');
  console.log('  ==========================================');
  console.log('  Spec-Driven Pipeline — Doctor');
  console.log('  ==========================================');
  console.log('');

  let allGood = true;

  // ─── Prerequisites ──────────────────────────────────────────
  console.log('  Prerequisites:');
  allGood = check('Node.js', 'node --version', '18') && allGood;
  allGood = check('Git', 'git --version') && allGood;

  // ─── CLI Agents ─────────────────────────────────────────────
  console.log('');
  console.log('  CLI agents:');

  const claudeOk = check('Claude Code', 'claude --version');
  allGood = claudeOk && allGood;

  const geminiOk = check('Gemini CLI', 'gemini --version');
  allGood = geminiOk && allGood;

  const qwenOk = check('Qwen Code', 'qwen --version');
  allGood = qwenOk && allGood;

  // ─── Authentication ─────────────────────────────────────────
  console.log('');
  console.log('  Authentication:');

  if (claudeOk) {
    const claudeAuth = checkAuth('Claude Code', 'claude -p "echo ok" --max-turns 1');
    allGood = claudeAuth && allGood;
    if (!claudeAuth) {
      console.log(`    ${YELLOW}→${NC} Run ${BOLD}claude${NC} interactively to sign in (needs Pro/Max/Teams/Enterprise account)`);
    }
  } else {
    console.log(`    ${RED}✗${NC}  Claude Code: not installed`);
    console.log(`    ${YELLOW}→${NC} Install: ${BOLD}curl -fsSL https://claude.ai/install.sh | bash${NC}`);
    console.log(`    ${YELLOW}→${NC} Or: ${BOLD}npm install -g @anthropic-ai/claude-code${NC}`);
  }

  if (geminiOk) {
    const geminiAuth = checkAuth('Gemini CLI', 'gemini -p "echo ok" --sandbox');
    allGood = geminiAuth && allGood;
    if (!geminiAuth) {
      console.log(`    ${YELLOW}→${NC} Run ${BOLD}gemini${NC} interactively to sign in with your Google account (free)`);
    }
  } else {
    console.log(`    ${RED}✗${NC}  Gemini CLI: not installed`);
    console.log(`    ${YELLOW}→${NC} Install: ${BOLD}npm install -g @google/gemini-cli${NC}`);
  }

  if (qwenOk) {
    const qwenAuth = checkAuth('Qwen Code', 'qwen -p "echo ok" --max-turns 1');
    allGood = qwenAuth && allGood;
    if (!qwenAuth) {
      console.log(`    ${YELLOW}→${NC} Run ${BOLD}qwen${NC} interactively to sign in (free account at qwen.ai)`);
    }
  } else {
    console.log(`    ${RED}✗${NC}  Qwen Code: not installed`);
    console.log(`    ${YELLOW}→${NC} Install: ${BOLD}npm install -g @qwen-code/qwen-code${NC}`);
  }

  // ─── Pipeline Files ─────────────────────────────────────────
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

  // ─── Summary ────────────────────────────────────────────────
  console.log('');
  if (allGood) {
    console.log(`  ${GREEN}All tools installed and authenticated.${NC} You're ready to go.`);
  } else {
    console.log(`  ${YELLOW}Some issues detected.${NC} Fix the items above, then run doctor again.`);
    console.log(`  For full setup: ${BOLD}./scripts/setup.sh${NC}`);
  }
  console.log('');
}

function check(name, command, minVersion) {
  try {
    const output = execSync(command, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 10000 }).trim();
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

function checkAuth(name, command) {
  try {
    execSync(command, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 30000 });
    console.log(`  ${GREEN}✓${NC}  ${name}: authenticated`);
    return true;
  } catch (e) {
    console.log(`  ${YELLOW}⚠${NC}  ${name}: not authenticated`);
    return false;
  }
}

function checkFile(filePath) {
  if (fs.existsSync(filePath)) {
    console.log(`    ${GREEN}✓${NC} ${filePath}`);
  } else {
    console.log(`    ${RED}✗${NC} ${filePath} (missing)`);
  }
}

module.exports = { doctor };
