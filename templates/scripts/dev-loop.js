#!/usr/bin/env node
const { exec, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const readline = require("readline");
const util = require("util");

const execAsync = util.promisify(exec);

// ─── Formatting & Colors ─────────────────────────────────────────
const colors = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  blue: "\x1b[34m",
  bold: "\x1b[1m",
};
const log = {
  info: (msg) => console.log(`  ${msg}`),
  success: (msg) => console.log(`  ${colors.green}✓ ${msg}${colors.reset}`),
  warn: (msg) => console.log(`  ${colors.yellow}⚠ ${msg}${colors.reset}`),
  error: (msg) =>
    console.log(`\n  ${colors.red}✗ ERROR: ${msg}${colors.reset}`),
  header: (msg) =>
    console.log(
      `\n${colors.bold}══════════════════════════════════════════════════\n  ${msg}\n══════════════════════════════════════════════════${colors.reset}`,
    ),
};

// ─── Utilities ──────────────────────────────────────────────────
async function promptUser(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) =>
    rl.question(`  ${colors.blue}${question}${colors.reset}`, (answer) => {
      rl.close();
      resolve(answer.trim());
    }),
  );
}

// Executes a CLI command with a timeout, streaming output to a log file
async function runAgent(name, command, logFile, timeoutSecs = 3600) {
  log.info(`Starting ${name}...`);
  return new Promise((resolve, reject) => {
    const process = spawn(command, {
      shell: true,
      timeout: timeoutSecs * 1000,
    });
    let output = "";

    if (logFile) fs.mkdirSync(path.dirname(logFile), { recursive: true });

    process.stdout.on("data", (data) => {
      output += data.toString();
      if (logFile) fs.appendFileSync(logFile, data.toString());
    });

    process.stderr.on("data", (data) => {
      output += data.toString();
      if (logFile) fs.appendFileSync(logFile, data.toString());
    });

    process.on("close", (code) => {
      if (code === 0) {
        log.success(`${name} completed.`);
        resolve(output);
      } else {
        log.warn(`${name} failed with exit code ${code}.`);
        reject({ code, output });
      }
    });
  });
}

// Extracts the session_id from Claude's output for cache continuity
function extractSessionId(output) {
  const match = output.match(/session_id=([^\s]+)/);
  return match ? match[1] : null;
}

// ─── Main Pipeline ──────────────────────────────────────────────
async function main() {
  const feature = process.argv[2];
  if (!feature || feature.startsWith("--")) {
    log.error("Usage: node dev-loop.js <feature-name>");
    process.exit(1);
  }

  const specFile = `aidev/specs/${feature}.md`;
  const planFile = `aidev/plans/${feature}-plan.md`;

  if (!fs.existsSync(specFile)) {
    log.error(`Spec file not found at ${specFile}`);
    process.exit(1);
  }

  // Generate Context
  log.info("Generating pristine CONTEXT.md...");
  const scriptsDir = process.env.AIDEV_SCRIPTS_DIR || path.join(__dirname);
  const genContextScript = path.join(scriptsDir, "generate-context.sh");
  await execAsync(`bash ${genContextScript}`);
  const contextPath = ".aidev/CONTEXT.md";

  // State Tracking
  let sessionID = null; // Single session for caching efficiency

  // ══════════════════════════════════════════════════════════
  // PHASE 0: SPEC REVIEW (Parallel + Iterative)
  // ══════════════════════════════════════════════════════════
  log.header("Phase 0 — Spec Review");
  let reviewRound = 1;
  while (true) {
    log.info(`── Round ${reviewRound} ──`);
    const geminiOut = `.aidev/reviews/spec/${feature}-gemini-r${reviewRound}.md`;
    const qwenOut = `.aidev/reviews/spec/${feature}-qwen-r${reviewRound}.md`;

    // 1. Parallel Review Generation
    if (fs.existsSync(geminiOut) && fs.existsSync(qwenOut)) {
      log.success(
        `Found existing Gemini and Qwen reviews for round ${reviewRound}. Skipping generation.`,
      );
    } else {
      log.info("Running Gemini + Qwen spec reviews in parallel...");

      const geminiPrompt = `Read ${contextPath}. Critique the feature spec at ${specFile} for missing error states and accessibility gaps. Return only markdown.`;
      const qwenPrompt = `Read ${contextPath}. Critique the feature spec at ${specFile} for race conditions and logic gaps. Return only markdown.`;

      const results = await Promise.allSettled([
        runAgent("Gemini Review", `gemini -p "${geminiPrompt}" --yolo`, null),
        runAgent("Qwen Review", `qwen -p "${qwenPrompt}" -y`, null),
      ]);
      
      if (results[0].status === 'fulfilled') fs.writeFileSync(geminiOut, results[0].value);
      if (results[1].status === 'fulfilled') fs.writeFileSync(qwenOut, results[1].value);
    }

    // 2. Claude Merge
    log.info("Claude: Merging feedback into spec...");
    const mergePrompt = `
      Read ${contextPath}. Two reviewers critiqued ${specFile}.
      Gemini: ${geminiOut}
      Qwen: ${qwenOut}
      
      Apply actionable feedback directly to ${specFile}. Append a summary to the '## Review Log' section. Do not write implementation code.
    `;

    try {
      const claudeCmd = sessionID 
        ? `claude -p "${mergePrompt}" --continue "${sessionID}" --dangerously-skip-permissions`
        : `claude -p "${mergePrompt}" --dangerously-skip-permissions`;
      
      const out = await runAgent(`Claude Merge (Round ${reviewRound})`, claudeCmd, null);
      if (!sessionID) sessionID = extractSessionId(out);
    } catch (err) {
      log.error(`Claude failed during spec merge.`);
      process.exit(1);
    }

    const answer = await promptUser(
      "Review git diff. Press Enter to commit and continue, or type 'again' for another round: ",
    );
    if (answer.toLowerCase() !== "again") {
      await execAsync(
        `git add ${specFile} .aidev/reviews/spec/ && git commit -m "spec(${feature}): finalise spec"`,
      );
      break;
    }
    reviewRound++;
  }

  // ══════════════════════════════════════════════════════════
  // PHASE 1: PLANNING
  // ══════════════════════════════════════════════════════════
  log.header("Phase 1 — Planning");

  const planPrompt = `Read ${contextPath} and ${specFile}. Generate a strict implementation plan to ${planFile} covering file hierarchy, state management, and integration points. Do not write code.`;

  try {
    const claudeCmd = sessionID 
      ? `claude -p "${planPrompt}" --continue "${sessionID}" --dangerously-skip-permissions`
      : `claude -p "${planPrompt}" --dangerously-skip-permissions`;
      
    const out = await runAgent("Claude Plan Generation", claudeCmd, null);
    if (!sessionID) sessionID = extractSessionId(out);
  } catch (err) {
    log.error("Plan generation failed.");
    process.exit(1);
  }

  // ══════════════════════════════════════════════════════════
  // PHASE 3: IMPLEMENTATION & AUTO-HEALING
  // ══════════════════════════════════════════════════════════
  log.header("Phase 3 — Implementation & Auto-Healing");

  const implPrompt = `Read ${contextPath}, ${specFile}, and ${planFile}. Implement the feature exactly as planned. Write the code to src/. NEVER modify existing tests.`;

  try {
    const claudeCmd = sessionID 
      ? `claude -p "${implPrompt}" --continue "${sessionID}" --dangerously-skip-permissions`
      : `claude -p "${implPrompt}" --dangerously-skip-permissions`;

    const out = await runAgent("Claude Implementation", claudeCmd, null);
    if (!sessionID) sessionID = extractSessionId(out);
  } catch (err) {
    log.error("Implementation failed.");
    process.exit(1);
  }

  // --- The Auto-Heal Loop ---
  let qualityPass = false;
  let retries = 0;
  const MAX_RETRIES = 2;

  while (!qualityPass && retries <= MAX_RETRIES) {
    log.info(`Running Quality Gates (Attempt ${retries + 1}/${MAX_RETRIES + 1})...`);
    qualityPass = true;
    let errorLog = "";

    // Run tests
    try {
      await execAsync("npm test");
      log.success("Tests passed");
    } catch (err) {
      log.warn("Tests failed");
      errorLog += `\nTEST ERRORS:\n${err.stdout}\n${err.stderr}`;
      qualityPass = false;
    }

    // Run linter
    try {
      await execAsync("npm run lint");
      log.success("Lint passed");
    } catch (err) {
      log.warn("Lint failed");
      errorLog += `\nLINT ERRORS:\n${err.stdout}\n${err.stderr}`;
      qualityPass = false;
    }

    if (!qualityPass) {
      if (retries < MAX_RETRIES && sessionID) {
        log.warn(`Quality gates failed. Routing errors back to Claude for auto-healing...`);

        const healPrompt = `The quality gates failed with these errors:\n\n${errorLog.slice(-4000)}\n\nFix the implementation in src/ to resolve these errors. Do NOT modify the tests.`;

        await runAgent(
          "Claude Auto-Heal",
          `claude -p "${healPrompt}" --continue "${sessionID}" --dangerously-skip-permissions`,
          null,
        );
        retries++;
      } else {
        log.error("Auto-healing exhausted. Please fix the remaining errors manually.");
        process.exit(1);
      }
    }
  }

  // Final Commit
  await execAsync(`git add -A && git commit -m "feat(${feature}): implement feature"`);
  log.success("Pipeline completed successfully! 🚀");
}

main().catch((err) => {
  log.error("Pipeline encountered a fatal error: " + err);
  process.exit(1);
});
