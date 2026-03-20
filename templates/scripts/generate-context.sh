#!/bin/bash
set -euo pipefail

# ─── Context Generator ──────────────────────────────────────────
# Generates CONTEXT.md — a single, comprehensive, machine-readable
# snapshot of the entire repository. This file is read by ALL LLM
# agents at the start of EVERY session, replacing the need to scan
# multiple doc files or source directories.
#
# Combines: docs/ARCHITECTURE.md + docs/CONVENTIONS.md +
#           docs/DATA-MODEL.md + docs/DECISIONS.md +
#           docs/DEPENDENCIES.md + live codebase scan
#
# Optimised for prompt caching: because this file is identical across
# all agent invocations within a pipeline run, it forms the stable
# prefix that gets cached at 90% discount on subsequent reads.
#
# Usage:
#   ./scripts/generate-context.sh
# ─────────────────────────────────────────────────────────────────

echo "[context] Generating CONTEXT.md..."

claude -p "
You are generating CONTEXT.md — a single file that ALL LLM agents read before
every task. It must give complete, accurate understanding of this project
without reading any other file.

Read every file in docs/ (ARCHITECTURE.md, CONVENTIONS.md, DATA-MODEL.md,
DECISIONS.md, DEPENDENCIES.md). Scan src/, tests/, specs/, plans/, and all
config files. Read package.json and any lock files.

Generate CONTEXT.md with ALL of the following sections. Do not skip any.

## Project Summary
One paragraph: what this project does, who it is for, current stage.

## Tech Stack and Commands
List the framework, language, styling, test runner, state management,
package manager. List the exact commands for test, lint, type check, dev.

## Conventions
Merge all content from docs/CONVENTIONS.md. Include naming rules, component
rules, state management patterns, testing conventions.

## Architecture
Merge all content from docs/ARCHITECTURE.md. Include directory map, data
flow, key patterns.

## Data Model
Merge all content from docs/DATA-MODEL.md. List every TypeScript interface
and type alias with fields and canonical source file.

## Architecture Decisions
Merge all content from docs/DECISIONS.md. Include decision number, what was
chosen, alternatives, and reasoning.

## Dependencies
Merge all content from docs/DEPENDENCIES.md. For any new packages not yet
documented, add them by reading package.json.

## File Map
Every file in src/ with a one-line description and line count, grouped by
directory. If src/ is empty, say so.

## Component Tree
React component hierarchy as a tree. Show parent-child and key props.
If no components exist, say so.

## State Architecture
Which stores exist, their state shapes, which components read/write each.
If no stores exist, say so.

## API Surface
Every API endpoint consumed, the calling function, request/response types.
If no API calls exist, say so.

## Test Coverage Map
For each feature area: which test files, test count, categories
(unit/integration/e2e/adversarial), and gaps.

## Recent Changes
Last 10 git commits with messages. If no commits, say so.

## Known Issues and TODOs
TODO comments in code, known bugs, unresolved review findings.

## Feature Status
For each spec in specs/: whether tests, plan, implementation, and review
are complete. Format as a table.

RULES:
- Be factual. Describe what IS, not what should be.
- Include line counts for every source file.
- This file must be SELF-CONTAINED. An agent reading ONLY this file should
  understand the entire project.
- Do NOT include instructions like 'read docs/ARCHITECTURE.md' — the content
  from those files should be INLINE in this file.
- If a section has no content yet (empty project), write a one-line note
  saying so rather than omitting the section.

Save to CONTEXT.md in the project root. Overwrite if it exists.
" --dangerously-skip-permissions

if [ -f "CONTEXT.md" ]; then
    LINES=$(wc -l < CONTEXT.md)
    echo "[context] Generated CONTEXT.md (${LINES} lines)"

    if git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
        git add CONTEXT.md
        git commit -m "docs: update CONTEXT.md" --no-verify 2>/dev/null || true
    fi
else
    echo "[context] Warning: CONTEXT.md was not created"
    exit 1
fi

echo "[context] Done."
