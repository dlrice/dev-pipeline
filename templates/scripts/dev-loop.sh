#!/bin/bash
set -euo pipefail

# ─── Spec-Driven Development Pipeline ───────────────────────────
# Orchestrates three LLM agents through a seven-phase development loop.
#
# CACHE OPTIMISATION: Claude Code invocations are grouped into two
# sessions to maximise prompt cache hits:
#   Session A (Planning): merge tests + generate plan + revise plan
#   Session B (Building): implement + fix adversarial failures
# Each session keeps its cache warm internally. The stable prefix
# (CONTEXT.md + CLAUDE.md + tool definitions) is paid once per session,
# then read from cache at 90% discount for subsequent turns.
#
# CONTEXT.md: A single file combining all project docs and codebase
# state. Generated at pipeline start and end. All agents read this
# one file instead of scanning multiple doc files separately.
#
# Usage:
#   ./scripts/dev-loop.sh <feature-name>              # Full pipeline
#   ./scripts/dev-loop.sh <feature-name> --from 2     # Start from phase 2
#   ./scripts/dev-loop.sh <feature-name> --only 0     # Run single phase
#   ./scripts/dev-loop.sh <feature-name> --force       # Skip complexity halts
# ─────────────────────────────────────────────────────────────────

# ─── Parse arguments ─────────────────────────────────────────────
FEATURE="${1:?Usage: ./scripts/dev-loop.sh <feature-name> [--from N] [--only N] [--force]}"
shift

FROM_PHASE=0
ONLY_PHASE=-1
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from) FROM_PHASE="$2"; shift 2 ;;
        --only) ONLY_PHASE="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SPEC_FILE="specs/${FEATURE}.md"
PLAN_FILE="plans/${FEATURE}-plan.md"
PLAN_GEMINI="reviews/plan-reviews/${FEATURE}-gemini.md"
PLAN_QWEN="reviews/plan-reviews/${FEATURE}-qwen.md"
REVIEW_FILE="reviews/adversarial/${FEATURE}-review.md"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="logs/${FEATURE}-${TIMESTAMP}.log"

# ─── Validation ──────────────────────────────────────────────────
if [ ! -f "$SPEC_FILE" ]; then
    echo "Error: spec file $SPEC_FILE not found"
    echo "Create one with: cp specs/_template.md $SPEC_FILE"
    exit 1
fi

mkdir -p logs reviews/spec-critiques reviews/plan-reviews reviews/adversarial \
         tests/gemini tests/qwen tests/adversarial tests/merged plans

# ─── Logging ─────────────────────────────────────────────────────
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Pipeline started: $(date)"
echo "Feature: $FEATURE"
echo "Log: $LOG_FILE"

# ─── Git branch ──────────────────────────────────────────────────
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != feat/${FEATURE}* ]]; then
    echo "Creating branch feat/${FEATURE}..."
    git checkout -b "feat/${FEATURE}" 2>/dev/null || git checkout "feat/${FEATURE}"
fi

# ─── Generate fresh CONTEXT.md ───────────────────────────────────
# Runs BEFORE any agent so all agents have current project state.
# This is the stable prefix that gets prompt-cached across all calls.
echo ""
echo "Generating fresh CONTEXT.md for this pipeline run..."
if [ -f "./scripts/generate-context.sh" ]; then
    ./scripts/generate-context.sh
fi

# ─── Complexity check helper ─────────────────────────────────────
check_complexity() {
    local output_file="$1"
    local phase_name="$2"

    if [ -f "$output_file" ] && grep -q "COMPLEXITY_LIMIT" "$output_file" 2>/dev/null; then
        echo ""
        echo "========================================================"
        echo "  ⚠  COMPLEXITY LIMIT — Feature flagged as too large"
        echo "========================================================"
        echo ""
        echo "  Detected in: $phase_name"
        echo "  Decomposition: specs/${FEATURE}-decomposition.md"
        echo ""
        echo "  To work on sub-tasks instead:"
        echo "    1. Review the decomposition file"
        echo "    2. Create specs for each sub-task"
        echo "    3. Run: ./scripts/dev-loop.sh <sub-task-name>"
        echo ""

        if [ "$FORCE" = true ]; then
            echo "  --force flag set. Continuing anyway (not recommended)."
            echo ""
        else
            echo "  To proceed anyway (not recommended):"
            echo "    ./scripts/dev-loop.sh ${FEATURE} --force"
            echo ""
            exit 0
        fi
    fi
}

# ─── Helper: should run phase? ───────────────────────────────────
should_run() {
    local phase=$1
    if [ "$ONLY_PHASE" -ge 0 ]; then
        [ "$phase" -eq "$ONLY_PHASE" ]
    else
        [ "$phase" -ge "$FROM_PHASE" ]
    fi
}


# ═════════════════════════════════════════════════════════════════
# PHASE 0 — Spec Hardening (Gemini + Qwen, parallel, free)
# ═════════════════════════════════════════════════════════════════
if should_run 0; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 0 — Spec Hardening"
    echo "══════════════════════════════════════════════════"

    GEMINI_OUT="reviews/spec-critiques/${FEATURE}-gemini.md"
    QWEN_OUT="reviews/spec-critiques/${FEATURE}-qwen.md"

    echo "[0/6] Running Gemini + Qwen in parallel..."

    gemini -p "
Read CONTEXT.md for full project state.
Read the feature spec at $SPEC_FILE.
Read GEMINI.md for your role and instructions.

FIRST, assess whether this feature is too complex for a single pipeline run.
A feature is too complex if it describes more than 3-4 screens, introduces more
than 5 new components, requires more than 3 API endpoints, would modify more
than 10 existing files, involves more than 2 independent state concerns, would
need more than 500 lines of new code, or contains independently-shippable parts.

If too complex: output COMPLEXITY_LIMIT: This feature should be split.
Generate a decomposition to specs/${FEATURE}-decomposition.md. Stop.

If not too complex: critique the spec for missing error states, unspecified
technical constraints, accessibility gaps, conflicts with existing architecture,
and ambiguous wording. Save to $GEMINI_OUT.
" --yolo > /tmp/gemini-phase0.out 2>&1 &
    GEMINI_PID=$!

    qwen -p "
Read CONTEXT.md for full project state.
Read the feature spec at $SPEC_FILE.

FIRST, assess whether this feature is too complex for a single pipeline run.
A feature is too complex if it describes more than 3-4 screens, introduces more
than 5 new components, requires more than 3 API endpoints, would modify more
than 10 existing files, involves more than 2 independent state concerns, would
need more than 500 lines of new code, or contains independently-shippable parts.

If too complex: output COMPLEXITY_LIMIT: This feature should be split.
Generate a decomposition to specs/${FEATURE}-decomposition.md. Stop.

If not too complex: critique the spec for ambiguous user flows, boundary
conditions, race conditions, and cases where two developers would implement
differently. Save to $QWEN_OUT.
" > /tmp/qwen-phase0.out 2>&1 &
    QWEN_PID=$!

    wait $GEMINI_PID || echo "Warning: Gemini exited with error"
    wait $QWEN_PID || echo "Warning: Qwen exited with error"

    check_complexity /tmp/gemini-phase0.out "Phase 0 — Gemini spec review"
    check_complexity /tmp/qwen-phase0.out "Phase 0 — Qwen spec review"

    echo ""
    echo "  Spec critiques ready:"
    echo "    - $GEMINI_OUT"
    echo "    - $QWEN_OUT"
    echo ""
    read -p "  Review both, update your spec, then press Enter to continue (or Ctrl+C to stop)..."
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 1 — Test Generation (Gemini + Qwen, parallel, free)
# ═════════════════════════════════════════════════════════════════
if should_run 1; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 1 — Test Generation"
    echo "══════════════════════════════════════════════════"

    echo "[1/6] Running Gemini (breadth) + Qwen (adversarial) in parallel..."

    gemini -p "
Read CONTEXT.md for full project state.
Read the feature spec at $SPEC_FILE.
Read GEMINI.md for your role and instructions.

Write comprehensive tests for this feature. Save to tests/gemini/.
Focus: happy paths, component rendering, accessibility, responsive, state transitions.
After writing, run them once to verify they compile (failures expected).
" --yolo &
    GEMINI_PID=$!

    qwen -p "
Read CONTEXT.md for full project state.
Read the feature spec at $SPEC_FILE.

Write adversarial tests for this feature. Save to tests/qwen/.
Focus: error states, empty/null data, boundary values, rapid interaction,
network failures, malformed data, concurrent state changes.
After writing, run them once to verify they compile.
" &
    QWEN_PID=$!

    wait $GEMINI_PID || echo "Warning: Gemini exited with error"
    wait $QWEN_PID || echo "Warning: Qwen exited with error"

    echo "  Phase 1 complete. Tests in tests/gemini/ and tests/qwen/."
fi


# ═════════════════════════════════════════════════════════════════
# CLAUDE SESSION A — Planning (merge + plan + revise)
# ═════════════════════════════════════════════════════════════════
#
# Cache strategy: CONTEXT.md + CLAUDE.md form the stable prefix.
# Written to cache on first turn (~1.25x cost), then read from
# cache on turns 2 and 3 (~0.1x cost = 90% saving).
#
# Three tasks in one session instead of three separate invocations
# saves two cold cache writes.
# ═════════════════════════════════════════════════════════════════
if should_run 2; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Claude Session A — Merge + Plan + Revise"
    echo "  (single session for prompt cache efficiency)"
    echo "══════════════════════════════════════════════════"

    echo "  [2/6] Task 1: Merging test suites..."

    claude -p "
Read CONTEXT.md for full project state. Read CLAUDE.md for your instructions.

You have THREE tasks to complete in sequence in this session.

───────────────────────────────────────────────────
TASK 1 of 3: Merge test suites
───────────────────────────────────────────────────
Two independently-generated test suites exist:
- tests/gemini/ — breadth tests (happy paths, accessibility)
- tests/qwen/ — adversarial tests (failures, edge cases)

Merge into tests/merged/:
1. Read every test file in both directories
2. Deduplicate (keep the more thorough version of overlapping tests)
3. Resolve naming conflicts
4. Fix all imports for consistency

Run tests to verify compilation (failures expected — no implementation yet).
Fix compilation errors only. Do NOT write implementation code.
Report: total test count and brief coverage summary.

───────────────────────────────────────────────────
TASK 2 of 3: Generate implementation plan
───────────────────────────────────────────────────
Read the feature spec at $SPEC_FILE.
Read the merged test suite in tests/merged/.

FIRST assess complexity. If the merged test suite has more than 50 tests,
or implementation needs more than 8 new files, more than 500 lines of code,
or involves more than 2 independent concerns:
  Output COMPLEXITY_LIMIT: This feature should be split.
  Generate decomposition to specs/${FEATURE}-decomposition.md. Stop entirely.

Otherwise, generate an implementation plan to $PLAN_FILE covering:
- Files to create or modify (one-line description each)
- Component hierarchy (what renders what, key props)
- State management (which stores, state shape, data flow)
- New types or interfaces needed
- Integration points with existing code
- Implementation order (dependency-based)
- Risk areas (complex logic, performance, tricky CSS)

Do NOT write implementation code. Blueprint only.

───────────────────────────────────────────────────
TASK 3 of 3: Revise plan based on reviews
───────────────────────────────────────────────────
After generating the plan, PAUSE. The pipeline will run Gemini and Qwen
to review the plan. Their reviews will appear at:
- $PLAN_GEMINI
- $PLAN_QWEN

Once those files exist, read both reviews and revise $PLAN_FILE:
- Address valid feedback by updating the plan
- For feedback you disagree with, add a note explaining why
- Add a '## Revision Notes' section at the end

Report when all three tasks are done.
" --dangerously-skip-permissions > /tmp/claude-sessionA.out 2>&1 &
    CLAUDE_A_PID=$!

    # Poll for plan file to appear (Tasks 1-2 complete)
    echo "  Waiting for test merge and plan generation..."
    PLAN_APPEARED=false
    for i in $(seq 1 360); do  # 30 min max wait
        if [ -f "$PLAN_FILE" ]; then
            PLAN_APPEARED=true
            break
        fi
        if ! kill -0 $CLAUDE_A_PID 2>/dev/null; then
            break
        fi
        sleep 5
    done

    check_complexity /tmp/claude-sessionA.out "Session A — Claude plan generation"

    if [ "$PLAN_APPEARED" = true ]; then
        echo "  Plan generated. Running Gemini + Qwen reviews..."

        gemini -p "
Read CONTEXT.md for full project state. Read GEMINI.md.
Read the implementation plan at $PLAN_FILE.

Review for: architectural consistency with existing patterns, unnecessary
complexity, missed integration points, reusable existing components.
Save to $PLAN_GEMINI.
" --yolo &
        GEMINI_PID=$!

        qwen -p "
Read CONTEXT.md for full project state.
Read $PLAN_FILE, $SPEC_FILE, and tests/merged/.

Review for: over-engineering, missing error handling paths, unnecessary
state complexity, test scenarios the plan does not address.
Save to $PLAN_QWEN.
" &
        QWEN_PID=$!

        wait $GEMINI_PID || echo "Warning: Gemini exited with error"
        wait $QWEN_PID || echo "Warning: Qwen exited with error"
        echo "  Plan reviews complete."
    fi

    # Wait for Claude Session A to finish Task 3 (revision)
    wait $CLAUDE_A_PID || echo "Warning: Claude Session A exited with error"

    echo ""
    echo "  Plan ready: $PLAN_FILE"
    [ -f "$PLAN_GEMINI" ] && echo "  Reviews:    $PLAN_GEMINI"
    [ -f "$PLAN_QWEN" ] && echo "              $PLAN_QWEN"
    echo ""
    read -p "  Review the plan, then press Enter to implement (or Ctrl+C to stop)..."
fi


# ═════════════════════════════════════════════════════════════════
# CLAUDE SESSION B — Building (implement + adversarial fix)
# ═════════════════════════════════════════════════════════════════
#
# Cache strategy: Same stable prefix (CONTEXT.md + CLAUDE.md).
# Implementation is one long turn. Adversarial fix reuses the
# warm cache from the implementation turn.
# ═════════════════════════════════════════════════════════════════
if should_run 3; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Claude Session B — Implement + Fix"
    echo "  (single session for prompt cache efficiency)"
    echo "══════════════════════════════════════════════════"

    echo "  [3-4/6] Implementing feature..."

    claude -p "
Read CONTEXT.md for full project state. Read CLAUDE.md for your instructions.

You have TWO tasks to complete in sequence in this session.

───────────────────────────────────────────────────
TASK 1 of 2: Implement the feature
───────────────────────────────────────────────────
Read the feature spec at $SPEC_FILE.
Read the implementation plan at $PLAN_FILE.
Read the merged test suite in tests/merged/.

Before implementing: if at any point you find the scope exceeds
single-session capacity or you are making quality compromises
(skipping error handling, writing placeholder code, losing track of
state across files), STOP. Output COMPLEXITY_LIMIT and save a partial
decomposition to specs/${FEATURE}-decomposition.md showing what is
complete and what remains.

Otherwise: implement following the plan exactly.
- Create files in the order specified in the plan
- Follow the component hierarchy and state approach
- Run tests after each file or logical group of files
- Fix implementation (NEVER modify tests) until all pass

Once all tests pass, commit:
  git add -A
  git commit -m 'feat(${FEATURE}): implement feature'

Report: total tests passing, files created/modified.

───────────────────────────────────────────────────
TASK 2 of 2: Fix adversarial review failures
───────────────────────────────────────────────────
After Task 1, the pipeline will run Qwen for adversarial review.
Qwen will write additional tests to tests/adversarial/ and a review
to $REVIEW_FILE.

Once those files appear, run all tests (merged + adversarial).
If any new tests fail, fix the implementation in src/.
NEVER modify or delete any tests.

After all tests pass, commit:
  git add -A
  git commit -m 'fix(${FEATURE}): address adversarial review'

Report: which adversarial tests failed, what you changed.
" --dangerously-skip-permissions > /tmp/claude-sessionB.out 2>&1 &
    CLAUDE_B_PID=$!

    # Wait for implementation commit
    echo "  Waiting for implementation..."
    IMPL_DONE=false
    for i in $(seq 1 720); do  # 60 min max wait
        if git log --oneline -1 2>/dev/null | grep -q "feat(${FEATURE})" ; then
            IMPL_DONE=true
            break
        fi
        if ! kill -0 $CLAUDE_B_PID 2>/dev/null; then
            break
        fi
        sleep 5
    done

    check_complexity /tmp/claude-sessionB.out "Session B — Claude implementation"

    if [ "$IMPL_DONE" = true ]; then
        # Quality gate
        echo "  Implementation committed. Running quality gates..."
        npm test && echo "  ✓ Tests pass" || echo "  ⚠ Some tests failing"

        if command -v npx &> /dev/null && [ -f "tsconfig.json" ]; then
            npx tsc --noEmit 2>/dev/null || echo "  Warning: TypeScript errors detected"
        fi

        # Qwen adversarial review while Claude waits for Task 2
        echo ""
        echo "  [4/6] Running Qwen adversarial review..."

        qwen -p "
Read CONTEXT.md for full project state.
Read $SPEC_FILE and $PLAN_FILE.
Read every file in src/ that was created or modified for this feature.
Read every test in tests/merged/.

Find: spec compliance issues, security concerns (XSS, data exposure),
robustness gaps (missing error handling, race conditions, cleanup),
accessibility issues (missing ARIA, keyboard traps).

Write additional tests to tests/adversarial/.
Save review summary to $REVIEW_FILE.
Do NOT modify any files in src/.
"
        echo "  Adversarial review complete."
    fi

    # Wait for Claude Session B to finish (including adversarial fixes)
    wait $CLAUDE_B_PID || echo "Warning: Claude Session B exited with error"

    [ -f "$REVIEW_FILE" ] && echo "  Adversarial review: $REVIEW_FILE"
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 5 — Documentation (Gemini, free)
# ═════════════════════════════════════════════════════════════════
if should_run 5; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 5 — Documentation"
    echo "══════════════════════════════════════════════════"

    echo "[5/6] Gemini updating docs..."

    gemini -p "
Read CONTEXT.md for full project state. Read GEMINI.md.
Read plans/${FEATURE}-plan.md. Scan src/ for changes.

Update these doc files with any changes from this feature:
- docs/ARCHITECTURE.md — new directories, components, data flows
- docs/DATA-MODEL.md — new TypeScript interfaces or type changes
- docs/DEPENDENCIES.md — new packages installed
- docs/DECISIONS.md — new architectural decisions (leave Reasoning blank)

Do NOT remove existing content unless factually incorrect.
Commit: git add docs/ && git commit -m 'docs(${FEATURE}): update documentation'
" --yolo

    echo "  Phase 5 complete."
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 6 — Context Regeneration
# ═════════════════════════════════════════════════════════════════
if should_run 6 || [ "$ONLY_PHASE" -lt 0 ]; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 6 — Context Regeneration"
    echo "══════════════════════════════════════════════════"

    echo "[6/6] Regenerating CONTEXT.md with final state..."

    ./scripts/generate-context.sh

    echo "  Phase 6 complete."
fi


# ═════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════"
echo "  Pipeline complete: $FEATURE"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Artifacts:"
echo "    Spec:              $SPEC_FILE"
echo "    Spec critiques:    reviews/spec-critiques/"
echo "    Tests:             tests/merged/ + tests/adversarial/"
echo "    Plan:              $PLAN_FILE"
echo "    Plan reviews:      reviews/plan-reviews/"
echo "    Adversarial review: $REVIEW_FILE"
echo "    Context:           CONTEXT.md"
echo "    Log:               $LOG_FILE"
echo ""
echo "  Cache efficiency: Claude ran in 2 sessions (not 4+)."
echo "  CONTEXT.md formed the stable cached prefix across all turns."
echo ""
echo "  Git log:"
git log --oneline -10
echo ""
echo "  Your turn: review the diff, check the UI in browser,"
echo "  and decide whether to merge or iterate."
echo ""
