const path = require('path');
const { spawn } = require('child_process');

const GREEN = '\x1b[32m';
const NC = '\x1b[0m';

/**
 * Run the setup script to install CLI agents.
 */
async function setup() {
  const scriptPath = path.join(__dirname, '..', 'templates', 'scripts', 'setup.sh');

  console.log('');
  console.log(`  ${GREEN}▶${NC} Installing CLI agents...`);
  console.log('');

  const child = spawn('bash', [scriptPath], {
    cwd: process.cwd(),
    stdio: 'inherit',
  });

  return new Promise((resolve, reject) => {
    child.on('close', (code) => {
      if (code === 0) resolve();
      else process.exit(code);
    });
    child.on('error', (err) => {
      console.error(`  Failed to run setup: ${err.message}`);
      process.exit(1);
    });
  });
}

module.exports = { setup };
