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
# COST: This script is pure shell — no LLM invocation needed.
# It concatenates doc files and runs find/wc for the codebase scan.
#
# Usage:
#   Called automatically by aidev run
# ─────────────────────────────────────────────────────────────────

echo "[context] Generating .aidev/CONTEXT.md..."

OUTPUT=".aidev/CONTEXT.md"
CONFIG_FILE="aidev.config.json"

# ─── Helper: inline a doc file or write a fallback ───────────────
inline_doc() {
    local file="$1"
    local fallback="$2"
    if [ -f "$file" ]; then
        # Strip the first H1 heading line (we provide our own section heading)
        sed '1{/^# /d;}' "$file"
    else
        echo "$fallback"
    fi
}

# ─── Helper: generate file map for a directory ───────────────────
file_map() {
    local dir="$1"
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "No source files yet. The $dir/ directory is empty."
        return
    fi
    find "$dir" -type f \
        -not -name '*.map' \
        -not -path '*/node_modules/*' \
        -not -name '.gitkeep' \
        -not -name '.DS_Store' \
        2>/dev/null | sort | while read -r f; do
        local lines
        lines=$(wc -l < "$f" 2>/dev/null || echo "0")
        echo "- \`$f\` (${lines} lines)"
    done
}

# ─── Helper: extract TypeScript interfaces ───────────────────────
extract_types() {
    if [ -d "src" ]; then
        local output
        output=$(grep -rnE "^export\s+(interface|type)\s+" src/ 2>/dev/null || true)
        if [ -n "$output" ]; then
            echo "$output" | while read -r line; do
                echo "- $line"
            done
        else
            echo "No exported types found in src/."
        fi
    else
        echo "No src/ directory."
    fi
}

# ─── Helper: extract React component tree ────────────────────────
extract_components() {
    if [ -d "src" ]; then
        local count
        count=$(grep -rl "export.*function\|export.*const.*=.*(" src/ --include='*.tsx' --include='*.jsx' 2>/dev/null | wc -l || true)
        count=$((count + 0)) # Clean up newlines and spaces
        if [ "$count" -gt 0 ]; then
            echo "Found $count component files:"
            grep -rl "export.*function\|export.*const.*=.*(" src/ --include='*.tsx' --include='*.jsx' 2>/dev/null | sort | while read -r f; do
                local name
                name=$(basename "$f" | sed 's/\.\(tsx\|jsx\)$//')
                echo "- \`$f\` — $name"
            done
        else
            echo "No components yet."
        fi
    else
        echo "No components yet."
    fi
}

# ─── Helper: extract store files ─────────────────────────────────
extract_stores() {
    if [ -d "src" ]; then
        local stores
        stores=$(find src/ -name '*store*' -o -name '*Store*' -o -name '*slice*' -o -name '*Slice*' 2>/dev/null | head -20)
        if [ -n "$stores" ]; then
            echo "$stores" | while read -r f; do
                local lines
                lines=$(wc -l < "$f" 2>/dev/null || echo "0")
                echo "- \`$f\` (${lines} lines)"
            done
        else
            echo "No stores yet."
        fi
    else
        echo "No stores yet."
    fi
}

# ─── Helper: extract API calls ───────────────────────────────────
extract_api() {
    if [ -d "src" ]; then
        local found
        found=$(grep -rn "fetch(\|axios\.\|\.get(\|\.post(\|\.put(\|\.delete(\|\.patch(" src/ 2>/dev/null | head -30)
        if [ -n "$found" ]; then
            echo "$found" | while read -r line; do
                echo "- $line"
            done
        else
            echo "No API calls yet."
        fi
    else
        echo "No API calls yet."
    fi
}

# ─── Helper: count tests ─────────────────────────────────────────
count_tests() {
    local dir="$1"
    local label="$2"
    if [ -d "$dir" ]; then
        local files test_count
        files=$(find "$dir" -name '*.test.*' -o -name '*.spec.*' 2>/dev/null | wc -l || true)
        files=$((files + 0))
        test_count=$(grep -r "it(\|test(" "$dir" 2>/dev/null | wc -l || true)
        test_count=$((test_count + 0))
    fi
}

# ─── Helper: extract TODOs ───────────────────────────────────────
extract_todos() {
    if [ -d "src" ]; then
        local todos
        todos=$(grep -rn "TODO\|FIXME\|HACK\|XXX" src/ 2>/dev/null | head -30)
        if [ -n "$todos" ]; then
            echo "$todos" | while read -r line; do
                echo "- $line"
            done
        else
            echo "None found in source code."
        fi
    else
        echo "None yet."
    fi
}

# ─── Helper: feature status table ────────────────────────────────
feature_status() {
    if [ -d "aidev/specs" ]; then
        local specs
        specs=$(find aidev/specs/ -name '*.md' -not -name '_template.md' -not -name '*-decomposition.md' 2>/dev/null)
        if [ -n "$specs" ]; then
            echo "| Feature | Tests | Plan | Implementation | Review |"
            echo "|---------|-------|------|----------------|--------|"
            echo "$specs" | while read -r spec; do
                local name
                name=$(basename "$spec" .md)
                local has_tests="—" has_plan="—" has_impl="—" has_review="—"
                [ -d "tests" ] && [ -n "$(ls tests/ 2>/dev/null)" ] && has_tests="✓"
                [ -f "aidev/plans/${name}-plan.md" ] && has_plan="✓"
                git log --oneline 2>/dev/null | grep -q "feat(${name})" && has_impl="✓"
                [ -f ".aidev/reviews/implementation/${name}-gemini.md" ] || [ -f ".aidev/reviews/implementation/${name}-qwen.md" ] && has_review="✓"
                echo "| $name | $has_tests | $has_plan | $has_impl | $has_review |"
            done
        else
            echo "No features started yet."
        fi
    else
        echo "No features started yet."
    fi
}

# ─── Read tech stack from config ─────────────────────────────────
TECH_STACK="See aidev.config.json for details."
COMMANDS="See aidev.config.json for details."
if [ -f "$CONFIG_FILE" ] && command -v node &> /dev/null; then
    TECH_STACK=$(node -e "
const c = require('./$CONFIG_FILE');
const t = c.techStack || {};
const parts = [t.framework, t.language, t.styling, t.testRunner, t.e2eRunner, t.stateManagement].filter(Boolean);
console.log(parts.map(p => '- ' + p.charAt(0).toUpperCase() + p.slice(1)).join('\n'));
" 2>/dev/null || echo "See aidev.config.json for details.")

    COMMANDS=$(node -e "
const c = require('./$CONFIG_FILE');
const cmd = c.commands || {};
const lines = [];
if (cmd.test) lines.push('- Test: \`' + cmd.test + '\`');
if (cmd.lint) lines.push('- Lint: \`' + cmd.lint + '\`');
if (cmd.typeCheck) lines.push('- Type check: \`' + cmd.typeCheck + '\`');
if (cmd.dev) lines.push('- Dev: \`' + cmd.dev + '\`');
console.log(lines.join('\n'));
" 2>/dev/null || echo "See aidev.config.json for details.")
fi

# ─── Build CONTEXT.md ────────────────────────────────────────────
cat > "$OUTPUT" << 'HEADER'
# Context

> This file is auto-generated by aidev.
> Do NOT edit manually. It is regenerated at the start and end of every pipeline run.
> All LLM agents read this file before starting any task.
> It combines all project documentation with a live codebase scan.

HEADER

{
    # Project Summary
    echo "## Project Summary"
    echo ""
    if [ -f "docs/ARCHITECTURE.md" ] && grep -q "\[Project overview" docs/ARCHITECTURE.md 2>/dev/null; then
        echo "Project pipeline is set up. Architecture docs contain placeholders — fill them in after first implementation."
    elif [ -f "docs/ARCHITECTURE.md" ]; then
        # Extract the Overview section if it exists
        sed -n '/^## Overview/,/^## /{ /^## Overview/d; /^## /d; p; }' docs/ARCHITECTURE.md 2>/dev/null | head -5
    else
        echo "New project. Pipeline infrastructure has been set up. No implementation yet."
    fi
    echo ""

    # Tech Stack and Commands
    echo "## Tech Stack and Commands"
    echo ""
    echo "$TECH_STACK"
    echo ""
    echo "$COMMANDS"
    echo ""

    # Conventions
    echo "## Conventions"
    echo ""
    inline_doc "docs/CONVENTIONS.md" "No conventions documented yet."
    echo ""

    # Architecture
    echo "## Architecture"
    echo ""
    inline_doc "docs/ARCHITECTURE.md" "No architecture documented yet."
    echo ""

    # Data Model
    echo "## Data Model"
    echo ""
    inline_doc "docs/DATA-MODEL.md" "No types defined yet."
    echo ""
    echo "### Extracted Types from Source"
    echo ""
    extract_types
    echo ""

    # Architecture Decisions
    echo "## Architecture Decisions"
    echo ""
    inline_doc "docs/DECISIONS.md" "No decisions recorded yet."
    echo ""

    # Dependencies
    echo "## Dependencies"
    echo ""
    inline_doc "docs/DEPENDENCIES.md" "See package.json."
    echo ""

    # File Map
    echo "## File Map"
    echo ""
    file_map "src"
    echo ""

    # Component Tree
    echo "## Component Tree"
    echo ""
    extract_components
    echo ""

    # State Architecture
    echo "## State Architecture"
    echo ""
    extract_stores
    echo ""

    # API Surface
    echo "## API Surface"
    echo ""
    extract_api
    echo ""

    # Test Coverage Map
    echo "## Test Coverage Map"
    echo ""
    count_tests "tests" "Merged tests"
    count_tests ".aidev/tests/gemini" "Gemini breadth tests"
    count_tests ".aidev/tests/qwen" "Qwen adversarial tests"
    if [ ! -d "tests" ] || [ -z "$(find tests/ -name '*.test.*' -o -name '*.spec.*' 2>/dev/null)" ]; then
        echo "No tests yet."
    fi
    echo ""

    # Recent Changes
    echo "## Recent Changes"
    echo ""
    if git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
        local_log=$(git log --oneline -10 2>/dev/null)
        if [ -n "$local_log" ]; then
            echo "$local_log" | while read -r line; do
                echo "- $line"
            done
        else
            echo "No commits yet."
        fi
    else
        echo "Not a git repository."
    fi
    echo ""

    # Known Issues and TODOs
    echo "## Known Issues and TODOs"
    echo ""
    extract_todos
    echo ""

    # Feature Status
    echo "## Feature Status"
    echo ""
    feature_status
    echo ""

} >> "$OUTPUT"

# ─── Report ───────────────────────────────────────────
if [ -f "$OUTPUT" ]; then
    LINES=$(wc -l < "$OUTPUT")
    echo "[context] Generated .aidev/CONTEXT.md (${LINES} lines)"
else
    echo "[context] Warning: .aidev/CONTEXT.md was not created"
    exit 1
fi

echo "[context] Done."