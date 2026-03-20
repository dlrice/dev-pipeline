const fs = require("fs");
const path = require("path");

/**
 * Generate ephemeral files into .aidev/ for a pipeline run.
 * Called by lib/run.js before invoking the pipeline script.
 *
 * Creates:
 *   .aidev/CLAUDE.md      — Claude agent instructions
 *   .aidev/GEMINI.md      — Gemini agent instructions
 *   .aidev/AGENTS.md      — Qwen agent instructions
 *   .aidev/reviews/spec/
 *   .aidev/reviews/plan/
 *   .aidev/reviews/implementation/
 *   .aidev/tests/gemini/
 *   .aidev/tests/qwen/
 *   .aidev/logs/
 *   .aidev/signals/
 */
function generateEphemeral(cwd, config) {
  const ephemeralDir = path.join(cwd, ".aidev");

  // Create directory structure
  const dirs = [
    "",
    "reviews/spec",
    "reviews/plan",
    "reviews/implementation",
    "tests/gemini",
    "tests/qwen",
    "logs",
    "signals",
  ];

  for (const dir of dirs) {
    fs.mkdirSync(path.join(ephemeralDir, dir), { recursive: true });
  }

  // Build template context from config
  const ctx = buildContext(config);

  // Generate agent instruction files
  fs.writeFileSync(
    path.join(ephemeralDir, "CLAUDE.md"),
    renderClaude(ctx)
  );
  fs.writeFileSync(
    path.join(ephemeralDir, "GEMINI.md"),
    renderGemini(ctx)
  );
  fs.writeFileSync(
    path.join(ephemeralDir, "AGENTS.md"),
    renderAgents(ctx)
  );
}

function buildContext(config) {
  const ts = config.techStack || {};
  const techStack = [
    ts.framework ? capitalize(ts.framework) : null,
    ts.language === "typescript" ? "TypeScript" : "JavaScript",
    ts.styling ? capitalize(ts.styling) : null,
    ts.testRunner ? capitalize(ts.testRunner) : null,
    ts.e2eRunner ? capitalize(ts.e2eRunner) : null,
    ts.stateManagement ? capitalize(ts.stateManagement) : null,
  ].filter(Boolean);

  return {
    techStackList: techStack,
    techStackString: techStack.join(", "),
    framework: ts.framework || "react",
    language: ts.language || "typescript",
    styling: ts.styling || "css",
    testRunner: ts.testRunner || "vitest",
    e2eRunner: ts.e2eRunner,
    stateManagement: ts.stateManagement,
    packageManager: ts.packageManager || "npm",
    commands: config.commands || {},
    customConventions: config.conventions || "",
    isTypeScript: ts.language === "typescript",
  };
}

function renderClaude(ctx) {
  return `# Project Context

Read .aidev/CONTEXT.md before starting any task. It contains everything you need
to know about this project: architecture, conventions, data model, decisions,
dependencies, file map, component tree, state architecture, test coverage,
and current feature status. It is auto-generated — do not modify it.

**First-run fallback:** If CONTEXT.md contains only stub content (e.g.
"No source files yet"), scan the codebase directly to understand the project
before proceeding.

Do not scan src/ to understand the project unless CONTEXT.md is a stub.
CONTEXT.md already summarises every file. Only read specific source files
when you need to modify them.

## Tech Stack
${ctx.techStackList.map((t) => `- ${t}`).join("\n")}

## Commands
- Test: \`${ctx.commands.test || "npm test"}\`
- Lint: \`${ctx.commands.lint || "npm run lint"}\`${ctx.isTypeScript ? `\n- Type check: \`${ctx.commands.typeCheck || "npx tsc --noEmit"}\`` : ""}
- Dev: \`${ctx.commands.dev || "npm run dev"}\`

## Your Role
You are the primary implementer and plan generator for this project.
You generate implementation plans, merge test suites, write all production
code, and fix code when reviews find gaps.

## Code Conventions
- Functional components only, no classes
${ctx.isTypeScript ? "- All components must have TypeScript props interfaces\n" : ""}- Use named exports, not default exports
- Keep components under 150 lines — extract if larger
- Accessibility: all interactive elements need aria labels
${ctx.customConventions ? `\n## Team Conventions\n${ctx.customConventions}\n` : ""}
## Testing Conventions
- Do not modify tests — fix the implementation instead
- If a test seems wrong, flag it in your output but still make it pass
- Run \`${ctx.commands.test || "npm test"}\` after every significant change

## Git Conventions
- Commit messages: \`feat({scope}): {description}\` or \`fix({scope}): {description}\`
- One logical change per commit

## What NOT To Do
- Do not modify files in aidev/specs/ or aidev/plans/
- Do not skip failing tests — fix the code, not the test
- Do not install new dependencies without noting them in your output
- Do not modify .aidev/CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any plan or implementation, read the \`complexity\` section
of \`aidev.config.json\` for the project's specific thresholds. If the
task exceeds any threshold (max new files, max tests, max new code lines,
or max independent concerns), output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`aidev/specs/{feature-name}-decomposition.md\` instead of proceeding.

During implementation, if you find yourself making quality compromises to fit
within your context window, stop and output the same signal with a partial
decomposition showing what is done and what remains.

## After Completing a Task
If you made any architectural decisions not already recorded in
docs/DECISIONS.md, append them before committing.
`;
}

function renderGemini(ctx) {
  return `# Project Context

Read .aidev/CONTEXT.md before starting any task. It contains everything you need
to know about this project: architecture, conventions, data model, decisions,
dependencies, file map, component tree, state architecture, test coverage,
and current feature status. It is auto-generated — do not modify it.

**First-run fallback:** If CONTEXT.md contains only stub content (e.g.
"No source files yet"), scan the codebase directly to understand the project
before proceeding.

Do not scan src/ to understand the project unless CONTEXT.md is a stub.
CONTEXT.md already summarises every file. Only read specific source files
when your task requires it.

## Tech Stack
${ctx.techStackList.map((t) => `- ${t}`).join("\n")}

## Your Role
You are the test author (breadth focus), spec reviewer, plan reviewer,
and documentation updater. You write tests BEFORE implementation exists.
Your tests define the contract between the spec and the code.

## Testing Conventions
- ${ctx.testRunner ? capitalize(ctx.testRunner) : "Vitest"} for unit/component tests
${ctx.framework === "react" ? "- React Testing Library for component tests\n" : ""}${ctx.e2eRunner ? `- ${capitalize(ctx.e2eRunner)} for e2e tests\n` : ""}- Describe blocks match spec sections
- Test names start with "should" and describe user-visible behaviour
- Example: \`it("should show error message when check-in is submitted empty")\`

## Review Conventions
When critiquing specs or plans, format each issue as:
1. **Section**: the specific part of the document
2. **Issue**: what is missing or ambiguous
3. **Suggestion**: a concrete fix or addition

## What NOT To Do
- Do not write implementation code
- Do not modify files in src/
- Do not mock internal implementation details
- Test behaviour, not structure
- Do not modify .aidev/CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any task, read the \`complexity\` section of
\`aidev.config.json\` for the project's specific thresholds. If the
feature exceeds any threshold, output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`aidev/specs/{feature-name}-decomposition.md\` instead of
proceeding.
`;
}

function renderAgents(ctx) {
  return `# Project Context

Read .aidev/CONTEXT.md before starting any task. It contains everything you need
to know about this project: architecture, conventions, data model, decisions,
dependencies, file map, component tree, state architecture, test coverage,
and current feature status. It is auto-generated — do not modify it.

**First-run fallback:** If CONTEXT.md contains only stub content (e.g.
"No source files yet"), scan the codebase directly to understand the project
before proceeding.

Do not scan src/ to understand the project unless CONTEXT.md is a stub.
CONTEXT.md already summarises every file. Only read specific source files
when your task requires it.

## Tech Stack
${ctx.techStackList.map((t) => `- ${t}`).join("\n")}

## Your Role
You are the adversarial test author (depth focus), spec reviewer, plan
reviewer, and implementation reviewer. You find what everyone else missed.

## Testing Conventions (Adversarial Focus)
- Write tests for failure modes, not happy paths
- Focus on: error states, empty/null data, boundary values, rapid user
  interaction, network failures, malformed API responses, race conditions
- Name tests descriptively: \`it("should handle double-submit without creating duplicate entries")\`

## Review Format
When reviewing implementations, use these sections:
- **Spec Compliance Issues**: where implementation diverges from spec intent
- **Security Concerns**: XSS, data exposure, injection risks
- **Robustness Gaps**: missing error handling, cleanup, race conditions
- **Accessibility Gaps**: missing ARIA, keyboard traps, contrast issues
- **Tests Written**: list each new test file and what it covers

## What NOT To Do
- Do not modify implementation code in src/ during review
- Do not modify existing tests — only add new ones
- Do not give stylistic opinions — focus on correctness and safety
- Do not modify .aidev/CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any task, read the \`complexity\` section of
\`aidev.config.json\` for the project's specific thresholds. If the
feature exceeds any threshold, output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`aidev/specs/{feature-name}-decomposition.md\` instead of
proceeding.
`;
}

function capitalize(s) {
  if (!s) return "";
  return s.charAt(0).toUpperCase() + s.slice(1);
}

module.exports = { generateEphemeral };
