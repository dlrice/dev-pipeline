const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

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
  // We check for credential files rather than running prompts,
  // because unauthenticated CLIs hang waiting for interactive login.
  console.log('');
  console.log('  Authentication:');

  if (claudeOk) {
    const claudeAuth = checkClaudeAuth();
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
    const geminiAuth = checkGeminiAuth();
    allGood = geminiAuth && allGood;
    if (!geminiAuth) {
      console.log(`    ${YELLOW}→${NC} Run ${BOLD}gemini${NC} interactively to sign in with your Google account (free)`);
    }
  } else {
    console.log(`    ${RED}✗${NC}  Gemini CLI: not installed`);
    console.log(`    ${YELLOW}→${NC} Install: ${BOLD}npm install -g @google/gemini-cli${NC}`);
  }

  if (qwenOk) {
    const qwenAuth = checkQwenAuth();
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
  checkFile('pipeline/config.json');
  checkFile('CLAUDE.md');
  checkFile('GEMINI.md');
  checkFile('AGENTS.md');
  checkFile('CONTEXT.md');
  checkFile('pipeline/scripts/dev-loop.sh');
  checkFile('pipeline/scripts/setup.sh');
  checkFile('pipeline/scripts/generate-context.sh');
  checkFile('pipeline/specs/_template.md');

  // ─── Summary ────────────────────────────────────────────────
  console.log('');
  if (allGood) {
    console.log(`  ${GREEN}All tools installed and authenticated.${NC} You're ready to go.`);
  } else {
    console.log(`  ${YELLOW}Some issues detected.${NC} Fix the items above, then run doctor again.`);
    console.log(`  For full setup: ${BOLD}./pipeline/scripts/setup.sh${NC}`);
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

// ─── Auth checks via credential files (instant, no hanging) ─────

function checkClaudeAuth() {
  const home = os.homedir();

  // Linux/Windows: credentials file
  if (fs.existsSync(path.join(home, '.claude', '.credentials.json'))) {
    console.log(`  ${GREEN}✓${NC}  Claude Code: authenticated`);
    return true;
  }

  // macOS: check Keychain
  if (process.platform === 'darwin') {
    try {
      execSync('security find-generic-password -s "claude-code"', {
        stdio: ['pipe', 'pipe', 'pipe'],
        timeout: 5000,
      });
      console.log(`  ${GREEN}✓${NC}  Claude Code: authenticated`);
      return true;
    } catch (e) {
      // Not in keychain
    }
  }

  // Fallback: ANTHROPIC_API_KEY env var
  if (process.env.ANTHROPIC_API_KEY) {
    console.log(`  ${GREEN}✓${NC}  Claude Code: authenticated (API key)`);
    return true;
  }

  console.log(`  ${YELLOW}⚠${NC}  Claude Code: not authenticated`);
  return false;
}

function checkGeminiAuth() {
  const home = os.homedir();

  // Settings file created after first successful auth
  if (fs.existsSync(path.join(home, '.gemini', 'settings.json'))) {
    console.log(`  ${GREEN}✓${NC}  Gemini CLI: authenticated`);
    return true;
  }

  // Application Default Credentials (gcloud auth)
  if (fs.existsSync(path.join(home, '.config', 'gcloud', 'application_default_credentials.json'))) {
    console.log(`  ${GREEN}✓${NC}  Gemini CLI: authenticated (gcloud ADC)`);
    return true;
  }

  // Fallback: GEMINI_API_KEY env var
  if (process.env.GEMINI_API_KEY) {
    console.log(`  ${GREEN}✓${NC}  Gemini CLI: authenticated (API key)`);
    return true;
  }

  console.log(`  ${YELLOW}⚠${NC}  Gemini CLI: not authenticated`);
  return false;
}

function checkQwenAuth() {
  const home = os.homedir();
  const settingsPath = path.join(home, '.qwen', 'settings.json');

  // Check settings.json for selectedType (indicates completed auth)
  if (fs.existsSync(settingsPath)) {
    try {
      const content = fs.readFileSync(settingsPath, 'utf8');
      if (content.includes('"selectedType"')) {
        console.log(`  ${GREEN}✓${NC}  Qwen Code: authenticated`);
        return true;
      }
    } catch (e) {
      // Can't read file
    }
  }

  // Fallback: OPENAI_API_KEY env var (Qwen's API key mode)
  if (process.env.OPENAI_API_KEY) {
    console.log(`  ${GREEN}✓${NC}  Qwen Code: authenticated (API key)`);
    return true;
  }

  console.log(`  ${YELLOW}⚠${NC}  Qwen Code: not authenticated`);
  return false;
}

function checkFile(filePath) {
  if (fs.existsSync(filePath)) {
    console.log(`    ${GREEN}✓${NC} ${filePath}`);
  } else {
    console.log(`    ${RED}✗${NC} ${filePath} (missing)`);
  }
}

module.exports = { doctor };
