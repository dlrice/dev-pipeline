# Spec-Driven Development Pipeline

An automated development pipeline that orchestrates three cloud-based LLM agents to produce high-quality code from markdown specifications.

**Claude Code** (paid, $20/mo) handles implementation and planning. **Gemini CLI** and **Qwen Code** (both free) handle spec review, test generation, implementation review, and documentation.

## Install into any repo

```bash
cd your-project
npx github:dlrice/dev-pipeline init
```

The `init` command will:

1. Scan your `package.json` and config files to detect your tech stack
2. Ask you to confirm what it found and fill any gaps
3. Generate all pipeline files (agent instructions, scripts, config, doc stubs)
4. Tell you what to do next

**Private repos:** If your repo is private, ensure the user has `gh auth login` configured or use a personal access token. Install with:

```bash
npx github:dlrice/dev-pipeline#main init
```

## Commands

```bash
# Onboard the pipeline into a new repo
npx github:dlrice/dev-pipeline init

# Update pipeline scripts in an existing repo (preserves config and docs)
npx github:dlrice/dev-pipeline update

# Check that all tools are installed
npx github:dlrice/dev-pipeline doctor
```

## After init

```bash
# Install CLI tools (Claude Code, Gemini CLI, Qwen Code)
./pipeline/scripts/setup.sh

# Authenticate each tool once
claude      # Claude Pro account
gemini      # Google account
qwen        # Qwen account (qwen.ai)

# Create a feature spec and run the pipeline
cp pipeline/specs/_template.md pipeline/specs/my-feature.md
# Edit the spec...
./pipeline/scripts/dev-loop.sh my-feature

# If the pipeline fails (e.g. Claude runs out of credits), just re-run:
./pipeline/scripts/dev-loop.sh my-feature     # auto-resumes from last failure

# To start over from scratch:
./pipeline/scripts/dev-loop.sh my-feature --reset
```

### Skipping Phases

Not every task needs every phase. In your spec file, there's a `## Pipeline Phases`
section listing all five phases. Add `skip` after any phase you don't need:

```markdown
## Pipeline Phases
- Phase 0: Spec Review
- Phase 1: Planning  skip
- Phase 2: Test Generation
- Phase 3: Implementation
- Phase 4: Documentation  skip
```

The progress dashboard will show skipped phases with ⏭ and the pipeline
will jump straight past them. This is especially useful for tasks that don't
fit the standard feature-development loop — for example, skip Test Generation
when the task *is* a test migration.

## Pipeline Phases

The pipeline produces **5 clean git commits** — one per phase:

| Phase               | Agent(s)                        | Commit prefix | Purpose                                       |
| ------------------- | ------------------------------- | ------------- | --------------------------------------------- |
| 0 — Spec Review     | Gemini + Qwen → Claude          | `spec()`      | Iterative review and refinement of the spec   |
| 1 — Planning        | Claude → Gemini + Qwen → Claude | `plan()`      | Generate plan, review, revise until ready      |
| 2 — Test Generation | Gemini + Qwen → Claude          | `test()`      | Write and merge test suites                    |
| 3 — Implementation  | Claude → Gemini + Qwen → Claude | `feat()`      | Implement, review, fix                         |
| 4 — Documentation   | Gemini                          | `docs()`      | Update project docs                            |

Each review phase (0, 1, 3) is **iterative** — after each review round, you see the git diff and choose to commit or run another round.

## Directory structure

All pipeline-internal files live under `pipeline/` to keep your repo root clean. Your own code, tests, and docs stay at root level.

```
your-project/
├── CLAUDE.md              ← Agent instructions (root, read by Claude)
├── GEMINI.md              ← Agent instructions (root, read by Gemini)
├── AGENTS.md              ← Agent instructions (root, read by Qwen)
├── CONTEXT.md             ← Auto-generated project context (not committed)
├── docs/                  ← Your project documentation
├── src/                   ← Your source code
├── tests/                 ← Your merged test suite
└── pipeline/
    ├── config.json        ← Pipeline configuration
    ├── specs/             ← Feature specifications
    ├── plans/             ← Implementation plans
    ├── scripts/           ← Pipeline automation scripts
    ├── reviews/
    │   ├── spec/          ← Spec review files
    │   ├── plan/          ← Plan review files
    │   └── implementation/← Implementation review files
    ├── tests/             ← Intermediate test suites (gemini/, qwen/)
    ├── logs/              ← Pipeline run logs
    └── signals/           ← Inter-phase coordination files
```

## What gets generated

| File                          | Purpose                                             | Overwritten on update?       |
| ----------------------------- | --------------------------------------------------- | ---------------------------- |
| `pipeline/config.json`        | Project configuration                               | No                           |
| `CLAUDE.md`                   | Claude Code instructions                            | No                           |
| `GEMINI.md`                   | Gemini CLI instructions                             | No                           |
| `AGENTS.md`                   | Qwen Code instructions                              | No                           |
| `CONTEXT.md`                  | Auto-generated project context (read by all agents) | No (regenerated by pipeline) |
| `pipeline/specs/_template.md` | Feature spec template                               | No                           |
| `docs/*.md`                   | Project context documents                           | No                           |
| `pipeline/scripts/*.sh`       | Pipeline scripts                                    | **Yes** (always updated)     |
| `.gitignore` additions        | Log exclusion                                       | Appended only                |

## Cost

| Tool              | Cost                        |
| ----------------- | --------------------------- |
| Claude Code (Pro) | $20/mo (~£17) per developer |
| Gemini CLI        | Free                        |
| Qwen Code         | Free                        |
| **Total**         | **~£17/mo per developer**   |

## Updating

When the pipeline tool gets improvements:

```bash
npx github:dlrice/dev-pipeline update
```

This updates the scripts to the latest version while preserving your config, docs, specs, reviews, and any customisations to agent instruction files.

## Platform Support

The pipeline scripts require **bash** and standard Unix utilities (`find`, `grep`, `wc`, `sed`, `timeout`).

| Platform         | Support                                    |
| ---------------- | ------------------------------------------ |
| macOS            | Full support                               |
| Linux            | Full support                               |
| Windows (WSL)    | Full support — run all commands inside WSL |
| Windows (native) | Not supported — use WSL                    |

**Note on `--dangerously-skip-permissions`:** The pipeline uses this flag to allow Claude Code to run without interactive permission prompts. This gives Claude unrestricted filesystem and command access during pipeline runs. Review the generated CLAUDE.md instructions to understand what Claude is permitted to do.

## Requirements

- Node.js 18+
- Git
- bash (macOS/Linux native, or WSL on Windows)
- Claude Pro subscription ($20/mo)
- Google account (for Gemini CLI)
- Qwen account (for Qwen Code — free at qwen.ai)
