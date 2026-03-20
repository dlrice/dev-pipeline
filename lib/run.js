const path = require("path");
const fs = require("fs");
const { execSync, spawn } = require("child_process");
const { generateEphemeral } = require("./generate");

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const NC = "\x1b[0m";

/**
 * Run the pipeline for a feature.
 *
 * 1. Reads aidev.config.json from the repo
 * 2. Creates/refreshes .aidev/ with ephemeral files (agent instructions, CONTEXT.md)
 * 3. Ensures aidev/specs/ and aidev/plans/ exist
 * 4. Invokes the dev-loop.js script bundled with the package
 */
async function run(feature, extraArgs) {
  const cwd = process.cwd();
  const configPath = path.join(cwd, "aidev.config.json");

  // Check config exists
  if (!fs.existsSync(configPath)) {
    console.error("  Error: aidev.config.json not found in this directory.");
    console.error('  Run "aidev init" first to set up the pipeline.');
    process.exit(1);
  }

  // Check spec exists
  const specFile = path.join(cwd, "aidev", "specs", `${feature}.md`);
  if (!fs.existsSync(specFile)) {
    console.error(`  Error: spec file not found at aidev/specs/${feature}.md`);
    console.error("  Create one with:");
    console.error(`    cp aidev/specs/_template.md aidev/specs/${feature}.md`);
    process.exit(1);
  }

  // Read config
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));

  // Generate ephemeral files into .aidev/
  console.log("");
  console.log(`  ${GREEN}▶${NC} Preparing pipeline for: ${feature}`);
  generateEphemeral(cwd, config);

  // Ensure .aidev is gitignored
  ensureGitignore(cwd);

  // Locate the dev-loop.js bundled with this package
  const scriptDir = path.join(__dirname, "..", "templates", "scripts");
  const devLoop = path.join(scriptDir, "dev-loop.js");

  if (!fs.existsSync(devLoop)) {
    console.error(
      "  Error: dev-loop.js not found in package. Reinstall aidev.",
    );
    process.exit(1);
  }

  // Build command args
  const cmdArgs = [devLoop, feature, ...extraArgs];

  // Pass package script directory as env var so dev-loop.js can find generate-context.sh
  const env = {
    ...process.env,
    AIDEV_SCRIPTS_DIR: scriptDir,
    AIDEV_EPHEMERAL_DIR: path.join(cwd, ".aidev"),
  };

  // Run the pipeline script
  console.log(`  ${GREEN}▶${NC} Starting pipeline...`);
  console.log("");

  // CHANGED: Spawning "node" instead of "bash"
  const child = spawn("node", cmdArgs, {
    cwd,
    env,
    stdio: "inherit",
  });

  return new Promise((resolve, reject) => {
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        process.exit(code);
      }
    });
    child.on("error", (err) => {
      console.error(`  Failed to start pipeline: ${err.message}`);
      process.exit(1);
    });
  });
}

/**
 * Ensure .aidev is in .gitignore
 */
function ensureGitignore(cwd) {
  const gitignorePath = path.join(cwd, ".gitignore");
  const entries = [".aidev/", ".aidev"];

  if (fs.existsSync(gitignorePath)) {
    let content = fs.readFileSync(gitignorePath, "utf8");
    if (!content.includes(".aidev")) {
      content += "\n# aidev ephemeral files\n.aidev/\n";
      fs.writeFileSync(gitignorePath, content);
    }
  } else {
    fs.writeFileSync(
      gitignorePath,
      "node_modules/\ndist/\n.env\n.env.local\n\n# aidev ephemeral files\n.aidev/\n",
    );
  }
}

module.exports = { run };
