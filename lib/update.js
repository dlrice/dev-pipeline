const path = require('path');
const fs = require('fs');

const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const NC = '\x1b[0m';

/**
 * Update: copies the latest spec template into aidev/specs/.
 * Since scripts ship with the global package, there's nothing else to update.
 */
async function update() {
  const cwd = process.cwd();

  console.log('');
  console.log('  ==========================================');
  console.log('  aidev — Update');
  console.log('  ==========================================');
  console.log('');

  // Check that aidev.config.json exists
  const configPath = path.join(cwd, 'aidev.config.json');
  if (!fs.existsSync(configPath)) {
    console.error('  Error: aidev.config.json not found.');
    console.error('  Run "aidev init" first to set up the pipeline.');
    process.exit(1);
  }

  // Update spec template
  const templateSrc = path.join(__dirname, '..', 'templates', 'specs', '_template.md');
  const templateDst = path.join(cwd, 'aidev', 'specs', '_template.md');

  if (fs.existsSync(templateSrc)) {
    fs.mkdirSync(path.dirname(templateDst), { recursive: true });
    fs.copyFileSync(templateSrc, templateDst);
    console.log(`  ${GREEN}✓${NC} aidev/specs/_template.md updated to latest version`);
  }

  console.log('');
  console.log('  Update complete. Pipeline scripts ship with the aidev package');
  console.log('  and are always at the latest version.');
  console.log(`  To update the package itself: ${GREEN}npm install -g aidev@latest${NC}`);
  console.log('');
}

module.exports = { update };
