const path = require("path");
const fs = require("fs");
const { detect } = require("./detect");
const { confirmDetection } = require("./prompt");

const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const NC = "\x1b[0m";

async function init() {
  const cwd = process.cwd();

  console.log("");
  console.log("  ==========================================");
  console.log("  aidev — Init");
  console.log("  ==========================================");
  console.log("");

  // Warn if already initialised
  const configPath = path.join(cwd, "aidev.config.json");
  if (fs.existsSync(configPath)) {
    console.log(`  ${YELLOW}!${NC} aidev.config.json already exists.`);
    console.log(
      '    Use --force to overwrite, or just run "aidev run <feature>".',
    );
    if (!process.argv.includes("--force")) {
      console.log("");
      return;
    }
    console.log("    --force flag set, continuing...");
    console.log("");
  }

  // Step 1: Detect tech stack
  console.log("  Scanning project...");
  const detected = detect(cwd);

  // Step 2: Confirm and ask
  const config = await confirmDetection(detected);

  // Step 3: Write aidev.config.json
  const configObj = {
    techStack: {
      framework: config.framework || "react",
      language: config.language || "typescript",
      styling: config.styling || "tailwindcss",
      testRunner: config.testRunner || "vitest",
      e2eRunner: config.e2eRunner || "playwright",
      stateManagement: config.stateManagement || "zustand",
      packageManager: config.packageManager || "npm",
    },
    commands: {
      test: config.commands.test || "npm test",
      lint: config.commands.lint || "npm run lint",
      typeCheck: config.commands.typeCheck || "npx tsc --noEmit",
      dev: config.commands.dev || "npm run dev",
    },
    agents: {
      implementer: "claude",
      reviewers: ["gemini", "qwen"],
      documenter: "gemini",
    },
    models: {
      claude: config.models?.claude || "sonnet",
      gemini: config.models?.gemini || "gemini-2.5-pro",
      qwen: config.models?.qwen || "qwen3-coder-plus",
    },
    complexity: {
      maxScreens:
        config.projectSize === "small"
          ? 2
          : config.projectSize === "large"
            ? 8
            : 4,
      maxNewComponents:
        config.projectSize === "small"
          ? 3
          : config.projectSize === "large"
            ? 10
            : 5,
      maxNewApiEndpoints:
        config.projectSize === "small"
          ? 1
          : config.projectSize === "large"
            ? 6
            : 3,
      maxModifiedFiles:
        config.projectSize === "small"
          ? 5
          : config.projectSize === "large"
            ? 20
            : 10,
      maxNewCodeLines:
        config.projectSize === "small"
          ? 250
          : config.projectSize === "large"
            ? 1000
            : 500,
      maxTests:
        config.projectSize === "small"
          ? 20
          : config.projectSize === "large"
            ? 100
            : 50,
    },
    conventions: config.customConventions || "",
  };

  fs.writeFileSync(configPath, JSON.stringify(configObj, null, 2) + "\n");
  console.log(`\n  ${GREEN}✓${NC} aidev.config.json`);

  // Step 4: Create aidev/specs/ and copy template
  const specsDir = path.join(cwd, "aidev", "specs");
  const plansDir = path.join(cwd, "aidev", "plans");
  fs.mkdirSync(specsDir, { recursive: true });
  fs.mkdirSync(plansDir, { recursive: true });

  const templateSrc = path.join(
    __dirname,
    "..",
    "templates",
    "specs",
    "_template.md",
  );
  const templateDst = path.join(specsDir, "_template.md");
  if (fs.existsSync(templateSrc)) {
    fs.copyFileSync(templateSrc, templateDst);
    console.log(`  ${GREEN}✓${NC} aidev/specs/_template.md`);
  }

  // Add .gitkeep to plans
  const plansGitkeep = path.join(plansDir, ".gitkeep");
  if (!fs.existsSync(plansGitkeep)) {
    fs.writeFileSync(plansGitkeep, "");
  }
  console.log(`  ${GREEN}✓${NC} aidev/plans/`);

  // Ensure .aidev is gitignored
  ensureGitignore(cwd);

  // Step 5: Create docs/ stubs if they don't exist
  const docsDir = path.join(cwd, "docs");
  if (!fs.existsSync(docsDir)) {
    fs.mkdirSync(docsDir, { recursive: true });
    const docStubs = [
      "ARCHITECTURE.md",
      "CONVENTIONS.md",
      "DATA-MODEL.md",
      "DEPENDENCIES.md",
      "DECISIONS.md",
    ];
    for (const stub of docStubs) {
      const stubSrc = path.join(__dirname, "..", "templates", "docs", stub);
      const stubDst = path.join(docsDir, stub);
      if (fs.existsSync(stubSrc) && !fs.existsSync(stubDst)) {
        fs.copyFileSync(stubSrc, stubDst);
        console.log(`  ${GREEN}✓${NC} docs/${stub}`);
      }
    }
  }

  // Next steps
  console.log("");
  console.log("  ==========================================");
  console.log("  Setup complete!");
  console.log("  ==========================================");
  console.log("");
  console.log("  Next steps:");
  console.log("");
  console.log("  1. Install CLI tools (if not already installed):");
  console.log(`     ${GREEN}aidev setup${NC}`);
  console.log("");
  console.log("  2. Authenticate each tool once:");
  console.log(`     ${GREEN}claude${NC}   — sign in with Claude Pro account`);
  console.log(`     ${GREEN}gemini${NC}   — sign in with Google account`);
  console.log(
    `     ${GREEN}qwen${NC}     — sign in with Qwen account (qwen.ai)`,
  );
  console.log("");
  console.log("  3. Start building:");
  console.log(`     cp aidev/specs/_template.md aidev/specs/my-feature.md`);
  console.log("     # Edit the spec");
  console.log(`     ${GREEN}aidev run my-feature${NC}`);
  console.log("");
}

function ensureGitignore(cwd) {
  const gitignorePath = path.join(cwd, ".gitignore");
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

module.exports = { init };
