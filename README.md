# aidev

A global CLI tool that orchestrates three LLM agents to produce high-quality code from markdown specifications.

**Claude Code** (paid, $20/mo) handles implementation and planning. **Gemini CLI** and **Qwen Code** (both free) handle spec review, test generation, implementation review, and documentation.

## Install

```bash
npm install -g github:dlrice/aidev
```

## Quick start

```bash
cd your-project
aidev init                    # Creates aidev.config.json + aidev/specs/
aidev setup                   # Installs CLI agents (Claude, Gemini, Qwen)

cp aidev/specs/_template.md aidev/specs/my-feature.md
# Edit the spec...
aidev run my-feature          # Runs the full pipeline
```

## Commands

```bash
aidev init                    # Set up aidev in a repo (creates config + spec dir)
aidev run <feature>           # Run the pipeline for a feature
aidev doctor                  # Check that all tools are installed and authenticated
aidev setup                   # Install CLI agents
aidev update                  # Update spec template to latest version
```

### Pipeline flags

```bash
aidev run my-feature --from 2    # Start from phase 2
aidev run my-feature --only 0    # Run single phase
aidev run my-feature --force     # Skip complexity halts
aidev run my-feature --reset     # Clear state and start over
```

### Auto-resume

If the pipeline fails (e.g. Claude runs out of credits), just re-run:

```bash
aidev run my-feature             # Automatically resumes from last failure
```

### Skipping phases

In your spec file, add `skip` after any phase you don't need:

```markdown
## Pipeline Phases
- Phase 0: Spec Review
- Phase 1: Planning  skip
- Phase 2: Test Generation
- Phase 3: Implementation
- Phase 4: Documentation  skip
```

## Pipeline phases

The pipeline produces **5 clean git commits** — one per phase:

| Phase               | Agent(s)                        | Commit prefix | Purpose                                       |
| ------------------- | ------------------------------- | ------------- | --------------------------------------------- |
| 0 — Spec Review     | Gemini + Qwen → Claude          | `spec()`      | Iterative review and refinement of the spec   |
| 1 — Planning        | Claude → Gemini + Qwen → Claude | `plan()`      | Generate plan, review, revise until ready      |
| 2 — Test Generation | Gemini + Qwen → Claude          | `test()`      | Write and merge test suites                    |
| 3 — Implementation  | Claude → Gemini + Qwen → Claude | `feat()`      | Implement, review, fix                         |
| 4 — Documentation   | Gemini                          | `docs()`      | Update project docs                            |

Each review phase (0, 1, 3) is **iterative** — after each review round, you see the git diff and choose to commit or run another round.

## What lives where

**In your repo** (committed):

```
your-project/
├── aidev.config.json       ← Created by aidev init
├── aidev/
│   ├── specs/               ← Feature specifications
│   └── plans/               ← Implementation plans
├── docs/                    ← Updated by pipeline
├── src/                     ← Your source code
└── tests/                   ← Merged test suite
```

**Ephemeral** (`.aidev/`, gitignored automatically):

```
.aidev/
├── CLAUDE.md                ← Agent instructions (generated at runtime)
├── GEMINI.md
├── AGENTS.md
├── CONTEXT.md               ← Project snapshot (generated at runtime)
├── reviews/                 ← Spec, plan, and implementation reviews
├── tests/                   ← Intermediate test suites
├── logs/                    ← Pipeline run logs
└── signals/                 ← State tracking for auto-resume
```

Everything the pipeline needs to run is generated fresh each time. Only your specs, plans, and actual code are committed.

## Cost

| Tool              | Cost                        |
| ----------------- | --------------------------- |
| Claude Code (Pro) | $20/mo (~£17) per developer |
| Gemini CLI        | Free                        |
| Qwen Code         | Free                        |
| **Total**         | **~£17/mo per developer**   |

## Platform support

| Platform         | Support                                    |
| ---------------- | ------------------------------------------ |
| macOS            | Full support                               |
| Linux            | Full support                               |
| Windows (WSL)    | Full support — run all commands inside WSL |
| Windows (native) | Not supported — use WSL                    |

## Requirements

- Node.js 18+
- Git
- bash (macOS/Linux native, or WSL on Windows)
- Claude Pro subscription ($20/mo)
- Google account (for Gemini CLI)
- Qwen account (for Qwen Code — free at qwen.ai)
