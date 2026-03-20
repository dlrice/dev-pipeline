const fs = require("fs");
const path = require("path");

const TEMPLATES_DIR = path.join(__dirname, "..", "templates");

/**
 * Generate all pipeline files in the target directory.
 * Never overwrites existing files unless force=true.
 */
function generate(cwd, config, { force = false } = {}) {
  const written = [];
  const skipped = [];

  // Directories to create
  // Pipeline-internal dirs live under pipeline/ to reduce root clutter.
  // docs/ and src/ stay at root (they're the developer's own files).
  const dirs = [
    "docs",
    "src",
    "pipeline/specs",
    "pipeline/plans",
    "pipeline/scripts",
    "pipeline/logs",
    "pipeline/signals",
    "pipeline/reviews/spec",
    "pipeline/reviews/plan",
    "pipeline/reviews/implementation",
    "pipeline/tests/gemini",
    "pipeline/tests/qwen",
    "tests", // merged tests = real project tests, stays at root
  ];

  for (const dir of dirs) {
    const fullPath = path.join(cwd, dir);
    if (!fs.existsSync(fullPath)) {
      fs.mkdirSync(fullPath, { recursive: true });
    }
    // Add .gitkeep to empty dirs
    const gitkeep = path.join(fullPath, ".gitkeep");
    if (!fs.existsSync(gitkeep) && isEmpty(fullPath)) {
      fs.writeFileSync(gitkeep, "");
    }
  }

  // Build template context
  const ctx = buildContext(config);

  // Generate config files (pipeline-internal → pipeline/)
  writeIfNew(
    cwd,
    "pipeline/config.json",
    renderConfig(config),
    force,
    written,
    skipped,
  );

  // Generate agent instruction files (root — agents read these directly)
  writeIfNew(cwd, "CLAUDE.md", renderClaude(ctx), force, written, skipped);
  writeIfNew(cwd, "GEMINI.md", renderGemini(ctx), force, written, skipped);
  writeIfNew(cwd, "AGENTS.md", renderAgents(ctx), force, written, skipped);
  writeIfNew(cwd, "CONTEXT.md", renderRepoState(), force, written, skipped);

  // Generate spec template (pipeline-internal)
  writeIfNew(
    cwd,
    "pipeline/specs/_template.md",
    readTemplate("specs/_template.md"),
    force,
    written,
    skipped,
  );

  // Generate doc stubs (root — developer's own documentation)
  writeIfNew(
    cwd,
    "docs/ARCHITECTURE.md",
    renderArchDocs(ctx),
    force,
    written,
    skipped,
  );
  writeIfNew(
    cwd,
    "docs/CONVENTIONS.md",
    renderConventionsDocs(ctx),
    force,
    written,
    skipped,
  );
  writeIfNew(
    cwd,
    "docs/DATA-MODEL.md",
    readTemplate("docs/DATA-MODEL.md"),
    force,
    written,
    skipped,
  );
  writeIfNew(
    cwd,
    "docs/DEPENDENCIES.md",
    readTemplate("docs/DEPENDENCIES.md"),
    force,
    written,
    skipped,
  );
  writeIfNew(
    cwd,
    "docs/DECISIONS.md",
    readTemplate("docs/DECISIONS.md"),
    force,
    written,
    skipped,
  );

  // Generate scripts (always update these — they're the pipeline logic)
  writeAlways(
    cwd,
    "pipeline/scripts/dev-loop.sh",
    readTemplate("scripts/dev-loop.sh"),
    written,
  );
  writeAlways(
    cwd,
    "pipeline/scripts/setup.sh",
    readTemplate("scripts/setup.sh"),
    written,
  );
  writeAlways(
    cwd,
    "pipeline/scripts/generate-context.sh",
    readTemplate("scripts/generate-context.sh"),
    written,
  );

  // Make scripts executable
  for (const script of [
    "pipeline/scripts/dev-loop.sh",
    "pipeline/scripts/setup.sh",
    "pipeline/scripts/generate-context.sh",
  ]) {
    try {
      fs.chmodSync(path.join(cwd, script), 0o755);
    } catch (e) {
      /* windows */
    }
  }

  // Append to .gitignore if it exists
  appendGitignore(cwd);

  return { written, skipped };
}

function buildContext(config) {
  const techStack = [
    config.framework ? `${capitalize(config.framework)}` : null,
    config.language === "typescript" ? "TypeScript" : "JavaScript",
    config.styling ? capitalize(config.styling) : null,
    config.testRunner ? capitalize(config.testRunner) : null,
    config.e2eRunner ? capitalize(config.e2eRunner) : null,
    config.stateManagement ? capitalize(config.stateManagement) : null,
  ].filter(Boolean);

  return {
    techStackList: techStack,
    techStackString: techStack.join(", "),
    framework: config.framework || "react",
    language: config.language || "typescript",
    styling: config.styling || "css",
    testRunner: config.testRunner || "vitest",
    e2eRunner: config.e2eRunner,
    stateManagement: config.stateManagement,
    packageManager: config.packageManager || "npm",
    commands: config.commands,
    customConventions: config.customConventions || "",
    isTypeScript: config.language === "typescript",
  };
}

function renderConfig(config) {
  const obj = {
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
      testWriterBreadth: "gemini",
      testWriterAdversarial: "qwen",
      reviewer: "qwen",
      documenter: "gemini",
    },
    phases: {
      skipPlanForSmallFeatures: true,
      autoProgressAfterPhase1: true,
      pauseAfterPhase0: true,
      pauseAfterPhase2: true,
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
  };
  return JSON.stringify(obj, null, 2) + "\n";
}

function renderClaude(ctx) {
  return `# Project Context

Read CONTEXT.md before starting any task. It contains everything you need
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
code, and fix code when adversarial tests find gaps.

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
- Do not modify files in pipeline/specs/, pipeline/plans/, or pipeline/reviews/
- Do not skip failing tests — fix the code, not the test
- Do not install new dependencies without noting them in your output
- Do not modify CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any plan or implementation, read the \`complexity\` section
of \`pipeline/config.json\` for the project's specific thresholds. If the
task exceeds any threshold (max new files, max tests, max new code lines,
or max independent concerns), output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`pipeline/specs/{feature-name}-decomposition.md\` instead of proceeding.

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

Read CONTEXT.md before starting any task. It contains everything you need
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
- Do not modify CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any task, read the \`complexity\` section of
\`pipeline/config.json\` for the project's specific thresholds. If the
feature exceeds any threshold, output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`pipeline/specs/{feature-name}-decomposition.md\` instead of
proceeding.
`;
}

function renderAgents(ctx) {
  return `# Project Context

Read CONTEXT.md before starting any task. It contains everything you need
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
reviewer, and adversarial code reviewer. You find what everyone else missed.

## Testing Conventions (Adversarial Focus)
- Write tests for failure modes, not happy paths
- Focus on: error states, empty/null data, boundary values, rapid user
  interaction, network failures, malformed API responses, race conditions
- Name tests descriptively: \`it("should handle double-submit without creating duplicate entries")\`

## Adversarial Review Format
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
- Do not modify CONTEXT.md (it is auto-generated)

## Complexity Detection
Before starting any task, read the \`complexity\` section of
\`pipeline/config.json\` for the project's specific thresholds. If the
feature exceeds any threshold, output
\`COMPLEXITY_LIMIT: This feature should be split.\` and generate a
decomposition to \`pipeline/specs/{feature-name}-decomposition.md\` instead of
proceeding.
`;
}

function renderRepoState() {
  return `# Context

> This file is auto-generated by \`./pipeline/scripts/generate-context.sh\`.
> Do NOT edit manually. It is regenerated at the start and end of every pipeline run.
> All LLM agents read this file before starting any task.
> It combines all project documentation with a live codebase scan.

## Project Summary
New project. Pipeline infrastructure has been set up. No implementation yet.

## Tech Stack and Commands
See pipeline/config.json for details.

## Conventions
See docs/CONVENTIONS.md (will be inlined here after first generation).

## Architecture
See docs/ARCHITECTURE.md (will be inlined here after first generation).

## Data Model
No types defined yet.

## Architecture Decisions
No decisions recorded yet.

## Dependencies
See package.json (not yet created).

## File Map
No source files yet. The src/ directory is empty.

## Component Tree
No components yet.

## State Architecture
No stores yet.

## API Surface
No API calls yet.

## Test Coverage Map
No tests yet.

## Recent Changes
Pipeline initialized.

## Known Issues and TODOs
None yet.

## Feature Status
No features started yet.
`;
}

function renderArchDocs(ctx) {
  return `# Architecture

> This file is maintained by Phase 4 of the dev pipeline and manual updates.
> It describes the system as it IS, not as it should be.

## Overview
[Project overview — what it does, who it's for, one paragraph.]

## Tech Stack
${ctx.techStackList.map((t) => `- ${t}`).join("\n")}

## Directory Map
\`\`\`
src/
├── components/    — ${ctx.framework ? capitalize(ctx.framework) : "UI"} components
├── hooks/         — Custom hooks for shared logic
${ctx.stateManagement ? `├── store/         — ${capitalize(ctx.stateManagement)} stores\n` : ""}${ctx.isTypeScript ? "├── types/         — TypeScript interfaces\n" : ""}├── utils/         — Pure functions, no side effects
└── api/           — API call functions
\`\`\`

## Data Flow
[Describe how data moves through the application.]

## Key Patterns
[Describe recurring patterns.]
`;
}

function renderConventionsDocs(ctx) {
  return `# Conventions

> This file is maintained by Phase 4 of the dev pipeline and manual updates.

## Naming
- Components: PascalCase (CheckInForm.${ctx.isTypeScript ? "tsx" : "jsx"})
- Hooks: camelCase with use prefix (useInterventions.${ctx.isTypeScript ? "ts" : "js"})
${ctx.stateManagement ? `- Stores: camelCase with Store suffix (checkInStore.${ctx.isTypeScript ? "ts" : "js"})\n` : ""}- Test files: {component}.test.${ctx.isTypeScript ? "tsx" : "jsx"} in tests/ directory

## Component Rules
- Max 150 lines, extract if larger
${ctx.isTypeScript ? "- Props interface exported and named {Component}Props\n" : ""}- Named exports only, no default exports
- Every interactive element needs aria-label or aria-labelledby

## Testing
- Test user behaviour, not implementation details
- Describe blocks match spec sections
- Test names start with "should"
${ctx.customConventions ? `\n## Team Conventions\n${ctx.customConventions}\n` : ""}`;
}

// ─── Utilities ──────────────────────────────────────────────────

function readTemplate(relativePath) {
  const fullPath = path.join(TEMPLATES_DIR, relativePath);
  if (fs.existsSync(fullPath)) {
    return fs.readFileSync(fullPath, "utf8");
  }
  return `# ${path.basename(relativePath, path.extname(relativePath))}\n\n[To be filled in.]\n`;
}

function writeIfNew(cwd, filePath, content, force, written, skipped) {
  const fullPath = path.join(cwd, filePath);
  if (fs.existsSync(fullPath) && !force) {
    skipped.push(filePath);
    return;
  }
  fs.mkdirSync(path.dirname(fullPath), { recursive: true });
  fs.writeFileSync(fullPath, content);
  written.push(filePath);
}

function writeAlways(cwd, filePath, content, written) {
  const fullPath = path.join(cwd, filePath);
  fs.mkdirSync(path.dirname(fullPath), { recursive: true });
  fs.writeFileSync(fullPath, content);
  written.push(filePath);
}

function appendGitignore(cwd) {
  const gitignorePath = path.join(cwd, ".gitignore");
  const additions = ["pipeline/logs/*.log", "pipeline/signals/", "CONTEXT.md"];

  if (fs.existsSync(gitignorePath)) {
    let content = fs.readFileSync(gitignorePath, "utf8");
    let appended = false;

    for (const addition of additions) {
      if (!content.includes(addition)) {
        content += `\n${addition}`;
        appended = true;
      }
    }
    if (appended) fs.writeFileSync(gitignorePath, content);
  } else {
    fs.writeFileSync(
      gitignorePath,
      `node_modules/\ndist/\n.env\n.env.local\npipeline/logs/*.log\npipeline/signals/\nCONTEXT.md\n.DS_Store\n`,
    );
  }
}

function isEmpty(dir) {
  try {
    const entries = fs.readdirSync(dir);
    return entries.length === 0;
  } catch (e) {
    return true;
  }
}

function capitalize(s) {
  if (!s) return "";
  return s.charAt(0).toUpperCase() + s.slice(1);
}

module.exports = { generate };
