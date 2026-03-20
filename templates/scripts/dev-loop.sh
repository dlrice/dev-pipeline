#!/bin/bash
set -euo pipefail

# ─── Spec-Driven Development Pipeline ───────────────────────────
# Orchestrates three LLM agents through a five-phase development loop.
#
# The pipeline produces 5 clean git commits:
#   1. spec(feature): final spec after iterative review
#   2. plan(feature): final plan after iterative review
#   3. test(feature): merged test suite
#   4. feat(feature): implementation passing all tests
#   5. docs(feature): updated documentation
#
# CACHE OPTIMISATION: Claude Code invocations are structured to
# maximise prompt cache hits:
#   Session A1: generate plan (cold start)
#   Session A2: revise plan based on reviews (--continue reuses cache)
#   Session B1: implement (cold start)
#   Session B2: fix review failures (--continue reuses cache)
# The stable prefix (CONTEXT.md + CLAUDE.md + tool definitions) is
# paid once per cold start, then read from cache at 90% discount
# for continued sessions.
#
# CONTEXT.md: Generated once at pipeline start. Not committed.
# All agents read this one file instead of scanning multiple doc
# files separately.
#
# Usage:
#   aidev run <feature-name>              # Full pipeline (auto-resumes)
#   aidev run <feature-name> --from 2     # Start from phase 2
#   aidev run <feature-name> --only 0     # Run single phase
#   aidev run <feature-name> --force       # Skip complexity halts
#   aidev run <feature-name> --reset       # Start over (clear state)
# ─────────────────────────────────────────────────────────────────

# ─── Configuration ───────────────────────────────────────────────
PIPELINE_START=$SECONDS
# Timeout for each agent invocation (seconds). Override with env var.
AGENT_TIMEOUT="${AGENT_TIMEOUT:-3600}"  # 60 minutes default

# ─── Parse arguments ─────────────────────────────────────────────
FEATURE="${1:?Usage: aidev run <feature-name> [--from N] [--only N] [--force] [--reset]}"
shift

FROM_PHASE=0
ONLY_PHASE=-1
FORCE=false
RESET_STATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from) FROM_PHASE="$2"; shift 2 ;;
        --only) ONLY_PHASE="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        --reset) RESET_STATE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

SPEC_FILE="aidev/specs/${FEATURE}.md"
PLAN_FILE="aidev/plans/${FEATURE}-plan.md"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE=".aidev/logs/${FEATURE}-${TIMESTAMP}.log"
STATE_FILE=".aidev/signals/${FEATURE}-state.json"

# Session IDs for Claude --continue
SESSION_A_ID=""
SESSION_B_ID=""

# Phase names for display
PHASE_NAMES=(
    "Spec Review"
    "Planning"
    "Test Generation"
    "Implementation"
    "Documentation"
)

# ─── State tracking ─────────────────────────────────────────────
# Tracks which phases have completed so the pipeline can auto-resume
# after failures (e.g. Claude running out of credits).
#
# State file: .aidev/signals/{feature}-state.json
# Format:     { "completed": [0,1], "failed": 2, "timestamp": "..." }
#
# On re-run without --from, the script detects the last successful
# phase and resumes from the next one. Use --reset to start over.

init_state() {
    if [ "$RESET_STATE" = true ] || [ ! -f "$STATE_FILE" ]; then
        echo '{"completed":[],"failed":null,"timestamp":"'"$(date -Iseconds)"'"}' > "$STATE_FILE"
    fi
}

read_state() {
    if [ -f "$STATE_FILE" ] && command -v node &> /dev/null; then
        node -e "
const s = require('./$STATE_FILE');
const completed = s.completed || [];
const failed = s.failed;
console.log('COMPLETED_PHASES=\"' + completed.join(' ') + '\"');
console.log('FAILED_PHASE=' + (failed !== null && failed !== undefined ? failed : -1));
" 2>/dev/null || echo 'COMPLETED_PHASES="" FAILED_PHASE=-1'
    else
        echo 'COMPLETED_PHASES=""'
        echo 'FAILED_PHASE=-1'
    fi
}

mark_phase_done() {
    local phase=$1
    if [ -f "$STATE_FILE" ] && command -v node &> /dev/null; then
        node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
if (!s.completed.includes($phase)) s.completed.push($phase);
s.completed.sort((a,b) => a-b);
if (s.failed === $phase) s.failed = null;
s.timestamp = new Date().toISOString();
fs.writeFileSync('$STATE_FILE', JSON.stringify(s, null, 2) + '\n');
" 2>/dev/null || true
    fi
}

mark_phase_failed() {
    local phase=$1
    if [ -f "$STATE_FILE" ] && command -v node &> /dev/null; then
        node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
s.failed = $phase;
s.timestamp = new Date().toISOString();
fs.writeFileSync('$STATE_FILE', JSON.stringify(s, null, 2) + '\n');
" 2>/dev/null || true
    fi
}

# ─── Spec-file progress log ────────────────────────────────────
# Appends structured progress entries to the spec's ## Pipeline Log
# section so users can see exactly what happened, which LLMs ran,
# and how long each phase took.

ensure_log_section() {
    if ! grep -q "^## Pipeline Log" "$SPEC_FILE" 2>/dev/null; then
        printf "\n## Pipeline Log\n" >> "$SPEC_FILE"
        printf "_Auto-generated by aidev. Do not edit above the log entries._\n\n" >> "$SPEC_FILE"
    fi
}

# log_to_spec <phase_num> <status> <agents> <duration_secs> [summary]
# Example: log_to_spec 0 "✓ done" "Gemini CLI, Qwen Code" 142 "2 reviews generated"
log_to_spec() {
    local phase=$1
    local status="$2"
    local agents="$3"
    local duration=$4
    local summary="${5:-}"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M")

    ensure_log_section

    # Format duration as Xm Ys
    local mins=$((duration / 60))
    local secs=$((duration % 60))
    local dur_str
    if [ "$mins" -gt 0 ]; then
        dur_str="${mins}m ${secs}s"
    else
        dur_str="${secs}s"
    fi

    {
        printf "### Phase %d — %s\n" "$phase" "${PHASE_NAMES[$phase]}"
        printf "- **Status:** %s\n" "$status"
        printf "- **Agents:** %s\n" "$agents"
        printf "- **Duration:** %s\n" "$dur_str"
        printf "- **Timestamp:** %s\n" "$ts"
        if [ -n "$summary" ]; then
            printf "- **Summary:** %s\n" "$summary"
        fi
        printf "\n"
    } >> "$SPEC_FILE"
}

# log_skip_to_spec <phase_num>
log_skip_to_spec() {
    local phase=$1
    ensure_log_section
    # Don't log duplicate skip entries on re-runs
    if grep -q "### Phase $phase.*" "$SPEC_FILE" 2>/dev/null; then
        return
    fi
    printf "### Phase %d — %s\n- **Status:** ⏭ skipped (per spec)\n\n" "$phase" "${PHASE_NAMES[$phase]}" >> "$SPEC_FILE"
}

# ─── Append to Review Log in spec ────────────────────────────────
# Appends a round entry to the spec's ## Review Log section.
append_review_log() {
    local round="$1"
    local phase_name="$2"
    local details="$3"

    if ! grep -q "^## Review Log" "$SPEC_FILE" 2>/dev/null; then
        printf "\n## Review Log\n" >> "$SPEC_FILE"
    fi

    {
        printf "### %s — Round %d\n" "$phase_name" "$round"
        printf "%s\n\n" "$details"
    } >> "$SPEC_FILE"
}

show_progress() {
    echo ""
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  Pipeline Progress: $FEATURE"
    echo "  ├─────────────────────────────────────────────┤"

    for i in 0 1 2 3 4; do
        local status="  "
        local marker="○"
        if echo "$COMPLETED_PHASES" | grep -qw "$i"; then
            marker="●"
            status="✓ "
        elif [ "$FAILED_PHASE" -eq "$i" ] 2>/dev/null; then
            marker="✗"
            status="✗ "
        fi
        # Mark skipped phases
        if echo "$SKIP_PHASES" | grep -qw "$i"; then
            marker="⏭"
            status="skip"
        # Highlight the phase we're about to run
        elif [ "$i" -eq "$FROM_PHASE" ] && [ "$status" = "  " ]; then
            marker="▶"
            status="► "
        fi
        printf "  │  %s Phase %d — %-25s %s │\n" "$marker" "$i" "${PHASE_NAMES[$i]}" "$status"
    done

    echo "  └─────────────────────────────────────────────┘"
    echo ""
}

# ─── Validation ──────────────────────────────────────────────────
if [ ! -f "$SPEC_FILE" ]; then
    echo "Error: spec file $SPEC_FILE not found"
    echo "Create one with: cp aidev/specs/_template.md $SPEC_FILE"
    exit 1
fi

mkdir -p .aidev/logs .aidev/reviews/spec .aidev/reviews/plan \
         .aidev/reviews/implementation .aidev/tests/gemini .aidev/tests/qwen \
         aidev/plans .aidev/signals tests

# ─── State: initialise and auto-resume ──────────────────────────
init_state
eval "$(read_state)"

# Auto-resume: if no explicit --from was given and we have completed phases,
# resume from the phase after the last completed one (or the failed one).
if [ "$FROM_PHASE" -eq 0 ] && [ "$ONLY_PHASE" -lt 0 ] && [ -n "$COMPLETED_PHASES" ]; then
    # Find the highest completed phase
    HIGHEST_COMPLETED=-1
    for p in $COMPLETED_PHASES; do
        if [ "$p" -gt "$HIGHEST_COMPLETED" ]; then
            HIGHEST_COMPLETED=$p
        fi
    done

    if [ "$FAILED_PHASE" -ge 0 ]; then
        # Resume from the failed phase
        FROM_PHASE=$FAILED_PHASE
        echo ""
        echo "  ⟳  Auto-resuming from Phase $FROM_PHASE (${PHASE_NAMES[$FROM_PHASE]}) — last failure point"
    elif [ "$HIGHEST_COMPLETED" -lt 4 ]; then
        # Resume from next phase after highest completed
        FROM_PHASE=$((HIGHEST_COMPLETED + 1))
        echo ""
        echo "  ⟳  Auto-resuming from Phase $FROM_PHASE (${PHASE_NAMES[$FROM_PHASE]}) — phases 0–${HIGHEST_COMPLETED} already done"
    else
        echo ""
        echo "  ✓  All phases already completed for $FEATURE."
        echo "     Use --reset to start over, or --from N to re-run a specific phase."
        exit 0
    fi
    echo "     Use --reset to start from scratch, or --from N to override."
fi

# ─── Parse skipped phases from spec ─────────────────────────────
# Reads the "## Pipeline Phases" section of the spec and finds lines
# containing "skip" (case-insensitive).  E.g.:
#   - Phase 1: Planning  skip
SKIP_PHASES=""
if [ -f "$SPEC_FILE" ]; then
    in_section=false
    while IFS= read -r line; do
        if echo "$line" | grep -q "^## Pipeline Phases"; then
            in_section=true
            continue
        fi
        if $in_section && echo "$line" | grep -q "^## "; then
            break
        fi
        if $in_section && echo "$line" | grep -qi "skip"; then
            phase_num=$(echo "$line" | grep -o 'Phase [0-9]' | grep -o '[0-9]')
            if [ -n "$phase_num" ]; then
                SKIP_PHASES="$SKIP_PHASES $phase_num"
            fi
        fi
    done < "$SPEC_FILE"
fi
if [ -n "$SKIP_PHASES" ]; then
    echo "  ⏭  Skipping phases:$SKIP_PHASES (per spec)"
    # Mark skipped phases as done so auto-resume doesn't get stuck on them
    for sp in $SKIP_PHASES; do
        mark_phase_done "$sp"
        log_skip_to_spec "$sp"
    done
fi

show_progress

# ─── Read complexity thresholds from config ──────────────────────
MAX_SCREENS=4
MAX_COMPONENTS=5
MAX_API_ENDPOINTS=3
MAX_MODIFIED_FILES=10
MAX_CODE_LINES=500
MAX_TESTS=50

if [ -f "aidev.config.json" ] && command -v node &> /dev/null; then
    eval "$(node -e "
const c = require('./aidev.config.json').complexity || {};
console.log('MAX_SCREENS=' + (c.maxScreens || 4));
console.log('MAX_COMPONENTS=' + (c.maxNewComponents || 5));
console.log('MAX_API_ENDPOINTS=' + (c.maxNewApiEndpoints || 3));
console.log('MAX_MODIFIED_FILES=' + (c.maxModifiedFiles || 10));
console.log('MAX_CODE_LINES=' + (c.maxNewCodeLines || 500));
console.log('MAX_TESTS=' + (c.maxTests || 50));
" 2>/dev/null)" || true
fi

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

# ─── Git checkpoint for rollback ─────────────────────────────────
CHECKPOINT_SHA=$(git rev-parse HEAD)
echo "Checkpoint: $CHECKPOINT_SHA (use 'git reset --hard $CHECKPOINT_SHA' to rollback)"

# ─── Generate fresh CONTEXT.md ───────────────────────────────────
echo ""
echo "Generating fresh CONTEXT.md for this pipeline run..."
if [ -f "$AIDEV_SCRIPTS_DIR/generate-context.sh" ]; then
    $AIDEV_SCRIPTS_DIR/generate-context.sh
fi

# ─── Agent runner with timeout ───────────────────────────────────
# Wraps an agent invocation with a timeout. Captures exit code.
# Usage: run_agent <name> <timeout_seconds> <command...>
run_agent() {
    local name="$1"
    local agent_timeout="$2"
    shift 2

    echo "  Starting $name (timeout: ${agent_timeout}s)..."
    if timeout "$agent_timeout" "$@"; then
        echo "  ✓ $name completed successfully."
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "  ✗ $name TIMED OUT after ${agent_timeout}s."
        else
            echo "  ✗ $name FAILED with exit code $exit_code."
        fi
        return $exit_code
    fi
}

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
        echo "  Decomposition: aidev/specs/${FEATURE}-decomposition.md"
        echo ""
        echo "  To work on sub-tasks instead:"
        echo "    1. Review the decomposition file"
        echo "    2. Create specs for each sub-task"
        echo "    3. Run: aidev run <sub-task-name>"
        echo ""

        if [ "$FORCE" = true ]; then
            echo "  --force flag set. Continuing anyway (not recommended)."
            echo ""
        else
            echo "  To proceed anyway (not recommended):"
            echo "    aidev run ${FEATURE} --force"
            echo ""
            exit 0
        fi
    fi
}

# ─── Helper: should run phase? ───────────────────────────────────
should_run() {
    local phase=$1
    # Check if phase is in the skip list (from spec's Pipeline Phases section)
    if echo "$SKIP_PHASES" | grep -qw "$phase"; then
        return 1
    fi
    if [ "$ONLY_PHASE" -ge 0 ]; then
        [ "$phase" -eq "$ONLY_PHASE" ]
    else
        [ "$phase" -ge "$FROM_PHASE" ]
    fi
}

# ─── Helper: require phase success ───────────────────────────────
# Checks that a required file exists before continuing.
require_file() {
    local file="$1"
    local description="$2"
    if [ ! -f "$file" ]; then
        echo ""
        echo "  ✗ ERROR: $description not found at $file"
        echo "  The previous phase may have failed. Check the log for details."
        echo "  Aborting pipeline."
        exit 1
    fi
}


# ═════════════════════════════════════════════════════════════════
# PHASE 0 — Spec Review (iterative: Gemini + Qwen → Claude merges)
# ═════════════════════════════════════════════════════════════════
# Two LLMs review the spec in parallel. Claude merges their feedback
# and applies changes directly to the spec. The user reviews the
# git diff and decides to iterate or commit.
# ═════════════════════════════════════════════════════════════════
if should_run 0; then
    PHASE_START=$SECONDS
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 0 — Spec Review"
    echo "══════════════════════════════════════════════════"

    REVIEW_ROUND=0

    while true; do
        REVIEW_ROUND=$((REVIEW_ROUND + 1))
        echo ""
        echo "  ── Review Round $REVIEW_ROUND ──"

        GEMINI_OUT=".aidev/reviews/spec/${FEATURE}-gemini-r${REVIEW_ROUND}.md"
        QWEN_OUT=".aidev/reviews/spec/${FEATURE}-qwen-r${REVIEW_ROUND}.md"

        echo "  Running Gemini + Qwen spec reviews in parallel..."

        GEMINI_EXIT=0
        QWEN_EXIT=0

        timeout "$AGENT_TIMEOUT" gemini -p "
Read .aidev/CONTEXT.md for full project state.
Read the feature spec at ${SPEC_FILE}.
Read .aidev/GEMINI.md for your role and instructions.

FIRST, assess whether this feature is too complex for a single pipeline run.
Read aidev.config.json for complexity thresholds. A feature is too complex
if it exceeds any of: ${MAX_SCREENS} screens, ${MAX_COMPONENTS} new components,
${MAX_API_ENDPOINTS} API endpoints, ${MAX_MODIFIED_FILES} modified files,
${MAX_CODE_LINES} lines of new code, or contains independently-shippable parts.

If too complex: output COMPLEXITY_LIMIT: This feature should be split.
Generate a decomposition to aidev/specs/${FEATURE}-decomposition.md. Stop.

If not too complex: critique the spec for missing error states, unspecified
technical constraints, accessibility gaps, conflicts with existing architecture,
and ambiguous wording. Save to ${GEMINI_OUT}.
" --yolo > /tmp/gemini-phase0.out 2>&1 &
        GEMINI_PID=$!

        timeout "$AGENT_TIMEOUT" qwen -p "
Read .aidev/CONTEXT.md for full project state.
Read the feature spec at ${SPEC_FILE}.
Read .aidev/AGENTS.md for your role and instructions.

FIRST, assess whether this feature is too complex for a single pipeline run.
Read aidev.config.json for complexity thresholds. A feature is too complex
if it exceeds any of: ${MAX_SCREENS} screens, ${MAX_COMPONENTS} new components,
${MAX_API_ENDPOINTS} API endpoints, ${MAX_MODIFIED_FILES} modified files,
${MAX_CODE_LINES} lines of new code, or contains independently-shippable parts.

If too complex: output COMPLEXITY_LIMIT: This feature should be split.
Generate a decomposition to aidev/specs/${FEATURE}-decomposition.md. Stop.

If not too complex: critique the spec for ambiguous user flows, boundary
conditions, race conditions, and cases where two developers would implement
differently. Save to ${QWEN_OUT}.
" -y > /tmp/qwen-phase0.out 2>&1 &
        QWEN_PID=$!

        wait $GEMINI_PID || GEMINI_EXIT=$?
        wait $QWEN_PID || QWEN_EXIT=$?

        if [ $GEMINI_EXIT -ne 0 ]; then
            echo "  ⚠ Gemini exited with code $GEMINI_EXIT"
        fi
        if [ $QWEN_EXIT -ne 0 ]; then
            echo "  ⚠ Qwen exited with code $QWEN_EXIT"
        fi

        # Check complexity
        check_complexity /tmp/gemini-phase0.out "Phase 0 — Gemini spec review"
        check_complexity /tmp/qwen-phase0.out "Phase 0 — Qwen spec review"

        echo ""
        echo "  Reviews saved:"
        [ -f "$GEMINI_OUT" ] && echo "    - $GEMINI_OUT" || echo "    - $GEMINI_OUT (missing — Gemini may have failed)"
        [ -f "$QWEN_OUT" ] && echo "    - $QWEN_OUT" || echo "    - $QWEN_OUT (missing — Qwen may have failed)"

        # Claude merges feedback and applies changes to spec
        echo ""
        echo "  Claude: Merging review feedback into spec..."

        MERGE_EXIT=0
        run_agent "Claude spec merge (round $REVIEW_ROUND)" "$AGENT_TIMEOUT" \
            claude -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/CLAUDE.md for your instructions.

Two reviewers have critiqued the feature spec at ${SPEC_FILE}:
- Gemini review: ${GEMINI_OUT}
- Qwen review: ${QWEN_OUT}

Read both reviews carefully. For each piece of feedback:
1. If valid and actionable: apply the change directly to ${SPEC_FILE}
2. If you disagree: note why in the Review Log

After making all changes, append a summary to the '## Review Log' section
of ${SPEC_FILE} in this format:

### Spec Review — Round ${REVIEW_ROUND}
- **Accepted:** [list of changes made]
- **Declined:** [list of feedback declined with brief reasons]
- **Timestamp:** $(date '+%Y-%m-%d %H:%M')

Do NOT modify any other files. Do NOT write implementation code.
" --dangerously-skip-permissions 2>&1 | tee /tmp/claude-spec-merge-r${REVIEW_ROUND}.out || MERGE_EXIT=$?

        if [ $MERGE_EXIT -ne 0 ]; then
            echo "  ⚠ Claude merge exited with code $MERGE_EXIT"
        fi

        echo ""
        echo "  ─────────────────────────────────────────────"
        echo "  Review the changes with: git diff ${SPEC_FILE}"
        echo "  ─────────────────────────────────────────────"
        echo ""
        read -p "  Press Enter to commit and continue, or type 'again' for another review round: " USER_CHOICE

        if [ "$USER_CHOICE" = "again" ]; then
            echo "  Starting another review round..."
            continue
        fi

        break
    done

    # Commit the final spec
    git add "$SPEC_FILE" .aidev/reviews/spec/
    git commit -m "spec(${FEATURE}): finalise spec after ${REVIEW_ROUND} review round(s)"

    mark_phase_done 0
    log_to_spec 0 "✓ done" "Gemini CLI, Qwen Code, Claude Code" $((SECONDS - PHASE_START)) "Spec reviewed (${REVIEW_ROUND} round(s)), changes merged and committed"
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 1 — Planning (iterative: Claude plans → Gemini + Qwen review)
# ═════════════════════════════════════════════════════════════════
# Claude generates the plan. Gemini and Qwen review it. Claude
# revises based on feedback. User reviews git diff. Iterate or commit.
#
# Cache strategy: Session A1 (plan) → A2 (revise via --continue)
# ═════════════════════════════════════════════════════════════════
if should_run 1; then
    PHASE_START=$SECONDS
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 1 — Planning"
    echo "══════════════════════════════════════════════════"

    # ── Session A1: Generate plan ─────────────────────────────────
    echo "  Claude: Generating implementation plan..."

    CLAUDE_A1_EXIT=0
    run_agent "Claude Session A1 (plan)" "$AGENT_TIMEOUT" \
        claude -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/CLAUDE.md for your instructions.
Read the feature spec at ${SPEC_FILE}.

FIRST assess complexity using these thresholds from aidev.config.json:
- Max screens: ${MAX_SCREENS}
- Max new components: ${MAX_COMPONENTS}
- Max API endpoints: ${MAX_API_ENDPOINTS}
- Max modified files: ${MAX_MODIFIED_FILES}
- Max new code lines: ${MAX_CODE_LINES}
- Max tests: ${MAX_TESTS}

If the feature exceeds these limits:
  Output COMPLEXITY_LIMIT: This feature should be split.
  Generate decomposition to aidev/specs/${FEATURE}-decomposition.md. Stop entirely.

Otherwise, generate an implementation plan to ${PLAN_FILE} covering:
- Files to create or modify (one-line description each)
- Component hierarchy (what renders what, key props)
- State management (which stores, state shape, data flow)
- New types or interfaces needed
- Integration points with existing code
- Implementation order (dependency-based)
- Risk areas (complex logic, performance, tricky CSS)

Do NOT write implementation code. Blueprint only.
" --dangerously-skip-permissions 2>&1 | tee /tmp/claude-sessionA1.out || CLAUDE_A1_EXIT=$?

    if [ $CLAUDE_A1_EXIT -ne 0 ]; then
        echo ""
        echo "  ✗ Claude Session A1 failed (exit code $CLAUDE_A1_EXIT)."
        echo "    Re-run the same command to auto-resume from this phase."
        mark_phase_failed 1
        log_to_spec 1 "✗ failed" "Claude Code" $((SECONDS - PHASE_START)) "Session A1 failed (exit $CLAUDE_A1_EXIT)"
        exit 1
    fi

    # Extract session ID for --continue
    SESSION_A_ID=$(grep -o 'session_id=[^ ]*' /tmp/claude-sessionA1.out 2>/dev/null | tail -1 | cut -d= -f2 || true)

    check_complexity /tmp/claude-sessionA1.out "Session A1 — Claude plan generation"
    require_file "$PLAN_FILE" "Implementation plan"

    # ── Iterative plan review loop ────────────────────────────────
    REVIEW_ROUND=0

    while true; do
        REVIEW_ROUND=$((REVIEW_ROUND + 1))
        echo ""
        echo "  ── Plan Review Round $REVIEW_ROUND ──"

        PLAN_GEMINI=".aidev/reviews/plan/${FEATURE}-gemini-r${REVIEW_ROUND}.md"
        PLAN_QWEN=".aidev/reviews/plan/${FEATURE}-qwen-r${REVIEW_ROUND}.md"

        echo "  Running Gemini + Qwen plan reviews in parallel..."

        GEMINI_EXIT=0
        QWEN_EXIT=0

        timeout "$AGENT_TIMEOUT" gemini -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/GEMINI.md for your role and instructions.
Read the feature spec at ${SPEC_FILE}.
Read the implementation plan at ${PLAN_FILE}.

Review for: architectural consistency with existing patterns, unnecessary
complexity, missed integration points, reusable existing components.
Save to ${PLAN_GEMINI}.
" --yolo &
        GEMINI_PID=$!

        timeout "$AGENT_TIMEOUT" qwen -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/AGENTS.md for your role and instructions.
Read ${PLAN_FILE} and ${SPEC_FILE}.

Review for: over-engineering, missing error handling paths, unnecessary
state complexity, test scenarios the plan does not address.
Save to ${PLAN_QWEN}.
" -y &
        QWEN_PID=$!

        wait $GEMINI_PID || GEMINI_EXIT=$?
        wait $QWEN_PID || QWEN_EXIT=$?

        if [ $GEMINI_EXIT -ne 0 ]; then
            echo "  ⚠ Gemini plan review exited with code $GEMINI_EXIT"
        fi
        if [ $QWEN_EXIT -ne 0 ]; then
            echo "  ⚠ Qwen plan review exited with code $QWEN_EXIT"
        fi

        echo "  Plan reviews saved."

        # Claude revises plan based on reviews
        echo ""
        echo "  Claude: Revising plan based on reviews..."

        REVISION_PROMPT="
Read the plan reviews:
- ${PLAN_GEMINI}
- ${PLAN_QWEN}

Revise ${PLAN_FILE} based on these reviews:
- Address valid feedback by updating the plan
- For feedback you disagree with, add a note explaining why

After making changes, append to the '## Review Log' section of ${SPEC_FILE}:

### Plan Review — Round ${REVIEW_ROUND}
- **Accepted:** [list of plan changes made]
- **Declined:** [list of feedback declined with brief reasons]
- **Timestamp:** $(date '+%Y-%m-%d %H:%M')

Do NOT write implementation code.
"
        # Try --continue if we have a session ID, otherwise start fresh
        if [ -n "$SESSION_A_ID" ]; then
            run_agent "Claude Session A2 (continue)" "$AGENT_TIMEOUT" \
                claude -p "$REVISION_PROMPT" --continue "$SESSION_A_ID" --dangerously-skip-permissions \
                2>&1 | tee /tmp/claude-sessionA2.out || \
            run_agent "Claude Session A2 (fresh)" "$AGENT_TIMEOUT" \
                claude -p "Read .aidev/CONTEXT.md. Read .aidev/CLAUDE.md. $REVISION_PROMPT" --dangerously-skip-permissions \
                2>&1 | tee /tmp/claude-sessionA2.out
        else
            run_agent "Claude Session A2 (fresh)" "$AGENT_TIMEOUT" \
                claude -p "Read .aidev/CONTEXT.md. Read .aidev/CLAUDE.md. $REVISION_PROMPT" --dangerously-skip-permissions \
                2>&1 | tee /tmp/claude-sessionA2.out
        fi

        echo ""
        echo "  ─────────────────────────────────────────────"
        echo "  Review the changes with: git diff ${PLAN_FILE}"
        echo "  ─────────────────────────────────────────────"
        echo ""
        read -p "  Press Enter to commit and continue, or type 'again' for another review round: " USER_CHOICE

        if [ "$USER_CHOICE" = "again" ]; then
            echo "  Starting another plan review round..."
            continue
        fi

        break
    done

    # Commit the final plan
    git add "$PLAN_FILE" "$SPEC_FILE" .aidev/reviews/plan/
    git commit -m "plan(${FEATURE}): finalise plan after ${REVIEW_ROUND} review round(s)"

    mark_phase_done 1
    log_to_spec 1 "✓ done" "Claude Code, Gemini CLI, Qwen Code" $((SECONDS - PHASE_START)) "Plan generated, reviewed (${REVIEW_ROUND} round(s)), and committed"
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 2 — Test Generation (Gemini + Qwen → Claude merges)
# ═════════════════════════════════════════════════════════════════
# Gemini writes breadth tests, Qwen writes adversarial tests.
# Claude merges them into tests/. Committed as one unit.
# ═════════════════════════════════════════════════════════════════
if should_run 2; then
    PHASE_START=$SECONDS
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 2 — Test Generation"
    echo "══════════════════════════════════════════════════"

    echo "  Running Gemini (breadth) + Qwen (adversarial) in parallel..."

    GEMINI_EXIT=0
    QWEN_EXIT=0

    timeout "$AGENT_TIMEOUT" gemini -p "
Read .aidev/CONTEXT.md for full project state.
Read the feature spec at ${SPEC_FILE}.
Read the implementation plan at ${PLAN_FILE}.
Read .aidev/GEMINI.md for your role and instructions.

Write comprehensive tests for this feature. Save to .aidev/tests/gemini/.
Focus: happy paths, component rendering, accessibility, responsive, state transitions.
After writing, run them once to verify they compile (failures expected).
" --yolo &
    GEMINI_PID=$!

    timeout "$AGENT_TIMEOUT" qwen -p "
Read .aidev/CONTEXT.md for full project state.
Read the feature spec at ${SPEC_FILE}.
Read the implementation plan at ${PLAN_FILE}.
Read .aidev/AGENTS.md for your role and instructions.

Write adversarial tests for this feature. Save to .aidev/tests/qwen/.
Focus: error states, empty/null data, boundary values, rapid interaction,
network failures, malformed data, concurrent state changes.
After writing, run them once to verify they compile.
" -y &
    QWEN_PID=$!

    wait $GEMINI_PID || GEMINI_EXIT=$?
    wait $QWEN_PID || QWEN_EXIT=$?

    if [ $GEMINI_EXIT -ne 0 ]; then
        echo "  ⚠ Gemini exited with code $GEMINI_EXIT"
    fi
    if [ $QWEN_EXIT -ne 0 ]; then
        echo "  ⚠ Qwen exited with code $QWEN_EXIT"
    fi

    # Claude merges test suites
    echo ""
    echo "  Claude: Merging test suites into tests/..."

    CLAUDE_MERGE_EXIT=0
    run_agent "Claude test merge" "$AGENT_TIMEOUT" \
        claude -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/CLAUDE.md for your instructions.

Two independently-generated test suites exist:
- .aidev/tests/gemini/ — breadth tests (happy paths, accessibility)
- .aidev/tests/qwen/ — adversarial tests (failures, edge cases)

Merge into tests/:
1. Read every test file in both directories
2. Deduplicate (keep the more thorough version of overlapping tests)
3. Resolve naming conflicts
4. Fix all imports for consistency

Run tests to verify compilation (failures expected — no implementation yet).
Fix compilation errors only. Do NOT write implementation code.
Report: total test count and brief coverage summary.
" --dangerously-skip-permissions 2>&1 | tee /tmp/claude-test-merge.out || CLAUDE_MERGE_EXIT=$?

    if [ $CLAUDE_MERGE_EXIT -ne 0 ]; then
        echo "  ⚠ Claude test merge exited with code $CLAUDE_MERGE_EXIT"
    fi

    # Commit tests
    git add tests/ .aidev/tests/
    git commit -m "test(${FEATURE}): generate and merge test suites"

    mark_phase_done 2
    log_to_spec 2 "✓ done" "Gemini CLI, Qwen Code, Claude Code" $((SECONDS - PHASE_START)) "Test suites generated, merged, and committed"
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 3 — Implementation (Claude Session B1 + Auto-Heal + Review)
# ═════════════════════════════════════════════════════════════════
# Claude implements the plan. Quality gates run. Gemini + Qwen
# review the implementation. Claude fixes any issues. Committed.
# ═════════════════════════════════════════════════════════════════
if should_run 3; then
    PHASE_START=$SECONDS
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 3 — Implementation"
    echo "══════════════════════════════════════════════════"

    echo "  Claude: Implementing feature..."

    CLAUDE_B1_EXIT=0
    run_agent "Claude Session B1 (implement)" "$AGENT_TIMEOUT" \
        claude -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/CLAUDE.md for your instructions.

───────────────────────────────────────────────────
Implement the feature
───────────────────────────────────────────────────
Read the feature spec at ${SPEC_FILE}.
Read the implementation plan at ${PLAN_FILE}.
Read the merged test suite in tests/.

Before implementing: if at any point you find the scope exceeds
single-session capacity or you are making quality compromises, STOP.
Output COMPLEXITY_LIMIT and save a partial decomposition to
aidev/specs/${FEATURE}-decomposition.md showing what is complete.

Otherwise: implement following the plan exactly.
- Create files in the order specified in the plan
- Follow the component hierarchy and state approach
- Run tests after each file or logical group of files
- Fix implementation (NEVER modify tests) until all pass

Report: total tests passing, files created/modified.
" --dangerously-skip-permissions 2>&1 | tee /tmp/claude-sessionB1.out || CLAUDE_B1_EXIT=$?

    if [ $CLAUDE_B1_EXIT -ne 0 ]; then
        echo ""
        echo "  ✗ Claude Session B1 failed (exit code $CLAUDE_B1_EXIT)."
        echo "    Re-run the same command to auto-resume from this phase."
        mark_phase_failed 3
        log_to_spec 3 "✗ failed" "Claude Code" $((SECONDS - PHASE_START)) "Session B1 failed (exit $CLAUDE_B1_EXIT)"
        exit 1
    fi

    # Extract session ID for --continue
    SESSION_B_ID=$(grep -o 'session_id=[^ ]*' /tmp/claude-sessionB1.out 2>/dev/null | tail -1 | cut -d= -f2 || true)

    check_complexity /tmp/claude-sessionB1.out "Session B1 — Claude implementation"

    # ── Auto-Healing Quality Gates ───────────────────────────────
    MAX_RETRIES=1
    RETRY_COUNT=0
    QUALITY_PASS=false

    while [ "$QUALITY_PASS" = false ] && [ "$RETRY_COUNT" -le "$MAX_RETRIES" ]; do
        echo ""
        if [ "$RETRY_COUNT" -gt 0 ]; then
            echo "  [Auto-Heal $RETRY_COUNT/$MAX_RETRIES] Retrying quality gates..."
        else
            echo "  Running quality gates..."
        fi

        QUALITY_PASS=true
        > /tmp/quality-errors.log # Clear previous errors

        # Test gate
        TEST_CMD=$(node -e "const c=require('./aidev.config.json');console.log(c.commands?.test||'npm test')" 2>/dev/null || echo "npm test")
        if ! eval "$TEST_CMD" >> /tmp/quality-errors.log 2>&1; then
            echo "  ✗ TESTS FAILED"
            QUALITY_PASS=false
        else
            echo "  ✓ Tests pass"
        fi

        # Lint gate
        LINT_CMD=$(node -e "const c=require('./aidev.config.json');console.log(c.commands?.lint||'')" 2>/dev/null || true)
        if [ -n "$LINT_CMD" ]; then
            if ! eval "$LINT_CMD" >> /tmp/quality-errors.log 2>&1; then
                echo "  ✗ LINT FAILED"
                QUALITY_PASS=false
            else
                echo "  ✓ Lint passes"
            fi
        fi

        # Type check gate
        if [ -f "tsconfig.json" ]; then
            TYPECHECK_CMD=$(node -e "const c=require('./aidev.config.json');console.log(c.commands?.typeCheck||'npx tsc --noEmit')" 2>/dev/null || echo "npx tsc --noEmit")
            if ! eval "$TYPECHECK_CMD" >> /tmp/quality-errors.log 2>&1; then
                echo "  ✗ TYPE CHECK FAILED"
                QUALITY_PASS=false
            else
                echo "  ✓ Type check passes"
            fi
        fi

        # If failed, attempt auto-heal using Claude
        if [ "$QUALITY_PASS" = false ]; then
            if [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ] && [ -n "$SESSION_B_ID" ]; then
                echo "  ⚠ Quality gates failed. Feeding errors back to Claude for auto-healing..."

                # Take the last 100 lines of the error log to avoid blowing up the context window
                tail -n 100 /tmp/quality-errors.log > /tmp/quality-errors-truncated.log

                run_agent "Claude auto-heal" "$AGENT_TIMEOUT" \
                    claude -p "
The quality gates (tests, linting, or type checking) failed with the following output:

$(cat /tmp/quality-errors-truncated.log)

Fix the implementation in src/ so that these errors are resolved.
NEVER modify the tests to bypass the errors.
" --continue "$SESSION_B_ID" --dangerously-skip-permissions 2>&1 | tee /tmp/claude-sessionB1-heal.out

                RETRY_COUNT=$((RETRY_COUNT + 1))
            else
                if [ "$FORCE" != true ]; then
                    echo ""
                    echo "  ⚠ Quality gates failed after $RETRY_COUNT attempts."
                    echo "  Review the errors, fix them manually, or use --force to proceed."
                    exit 1
                else
                    echo "  ⚠ Quality gates failed, but --force is set. Proceeding..."
                    QUALITY_PASS=true # Fake pass to exit loop
                fi
            fi
        fi
    done

    # ── Implementation review by Gemini + Qwen ─────────────────
    echo ""
    echo "  Running Gemini + Qwen implementation reviews..."

    IMPL_GEMINI=".aidev/reviews/implementation/${FEATURE}-gemini.md"
    IMPL_QWEN=".aidev/reviews/implementation/${FEATURE}-qwen.md"

    GEMINI_EXIT=0
    QWEN_EXIT=0

    timeout "$AGENT_TIMEOUT" gemini -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/GEMINI.md for your role and instructions.
Read ${SPEC_FILE} and ${PLAN_FILE}.
Read every file in src/ that was created or modified for this feature.
Read every test in tests/.

Review for: spec compliance, architectural consistency, code quality,
accessibility issues, performance concerns.
Save to ${IMPL_GEMINI}.
Do NOT modify any files in src/.
" --yolo &
    GEMINI_PID=$!

    timeout "$AGENT_TIMEOUT" qwen -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/AGENTS.md for your role and instructions.
Read ${SPEC_FILE} and ${PLAN_FILE}.
Read every file in src/ that was created or modified for this feature.
Read every test in tests/.

Find: spec compliance issues, security concerns (XSS, data exposure),
robustness gaps (missing error handling, race conditions, cleanup),
accessibility issues (missing ARIA, keyboard traps).
Save to ${IMPL_QWEN}.
Do NOT modify any files in src/.
" -y &
    QWEN_PID=$!

    wait $GEMINI_PID || GEMINI_EXIT=$?
    wait $QWEN_PID || QWEN_EXIT=$?

    if [ $GEMINI_EXIT -ne 0 ]; then
        echo "  ⚠ Gemini implementation review exited with code $GEMINI_EXIT"
    fi
    if [ $QWEN_EXIT -ne 0 ]; then
        echo "  ⚠ Qwen implementation review exited with code $QWEN_EXIT"
    fi

    # Claude addresses review findings
    echo ""
    echo "  Claude: Addressing implementation review findings..."

    FIX_PROMPT="
Read the implementation reviews:
- ${IMPL_GEMINI}
- ${IMPL_QWEN}

For each finding:
1. If it's a valid bug or gap: fix it in src/
2. If it's a style or preference issue: skip it
3. If you disagree: note why

Run ALL tests after making changes. NEVER modify tests.

After fixing, append to the '## Review Log' section of ${SPEC_FILE}:

### Implementation Review
- **Fixed:** [list of issues fixed]
- **Skipped:** [list of issues declined with reasons]
- **Timestamp:** $(date '+%Y-%m-%d %H:%M')
"

    if [ -n "$SESSION_B_ID" ]; then
        run_agent "Claude Session B2 (continue)" "$AGENT_TIMEOUT" \
            claude -p "$FIX_PROMPT" --continue "$SESSION_B_ID" --dangerously-skip-permissions \
            2>&1 | tee /tmp/claude-sessionB2.out || \
        run_agent "Claude Session B2 (fresh)" "$AGENT_TIMEOUT" \
            claude -p "Read .aidev/CONTEXT.md. Read .aidev/CLAUDE.md. $FIX_PROMPT" --dangerously-skip-permissions \
            2>&1 | tee /tmp/claude-sessionB2.out
    else
        run_agent "Claude Session B2 (fresh)" "$AGENT_TIMEOUT" \
            claude -p "Read .aidev/CONTEXT.md. Read .aidev/CLAUDE.md. $FIX_PROMPT" --dangerously-skip-permissions \
            2>&1 | tee /tmp/claude-sessionB2.out
    fi

    # Commit implementation
    git add -A
    git commit -m "feat(${FEATURE}): implement feature"

    if [ "$QUALITY_PASS" = true ]; then
        mark_phase_done 3
        log_to_spec 3 "✓ done" "Claude Code, Gemini CLI, Qwen Code" $((SECONDS - PHASE_START)) "Implementation complete, reviewed, quality gates passed"
    else
        mark_phase_failed 3
        log_to_spec 3 "✗ failed" "Claude Code" $((SECONDS - PHASE_START)) "Quality gates failed after $MAX_RETRIES auto-heal retries"
    fi
fi


# ═════════════════════════════════════════════════════════════════
# PHASE 4 — Documentation (Gemini, free)
# ═════════════════════════════════════════════════════════════════
if should_run 4; then
    PHASE_START=$SECONDS
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Phase 4 — Documentation"
    echo "══════════════════════════════════════════════════"

    echo "  Gemini: Updating docs..."

    GEMINI_EXIT=0
    run_agent "Gemini documentation" "$AGENT_TIMEOUT" \
        gemini -p "
Read .aidev/CONTEXT.md for full project state. Read .aidev/GEMINI.md for your role and instructions.
Read ${PLAN_FILE}. Scan src/ for changes.

Update these doc files with any changes from this feature:
- docs/ARCHITECTURE.md — new directories, components, data flows
- docs/DATA-MODEL.md — new TypeScript interfaces or type changes
- docs/DEPENDENCIES.md — new packages installed
- docs/DECISIONS.md — new architectural decisions (leave Reasoning blank)

Do NOT remove existing content unless factually incorrect.
" --yolo || GEMINI_EXIT=$?

    if [ $GEMINI_EXIT -ne 0 ]; then
        echo "  ⚠ Gemini documentation exited with code $GEMINI_EXIT"
    fi

    # Commit docs
    git add docs/ "$SPEC_FILE"
    git commit -m "docs(${FEATURE}): update documentation"

    echo "  Phase 4 complete."
    mark_phase_done 4
    log_to_spec 4 "✓ done" "Gemini CLI" $((SECONDS - PHASE_START)) "Documentation updated and committed"
fi


# ═════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════

# Re-read state for final progress display
eval "$(read_state)"

echo ""
echo "══════════════════════════════════════════════════"
echo "  Pipeline complete: $FEATURE"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Git log (should show 5 clean commits):"
git log --oneline -10
echo ""
echo "  Artifacts:"
echo "    Spec:           $SPEC_FILE"
echo "    Plan:           $PLAN_FILE"
echo "    Tests:          tests/"
echo "    Spec reviews:   .aidev/reviews/spec/"
echo "    Plan reviews:   .aidev/reviews/plan/"
echo "    Impl reviews:   .aidev/reviews/implementation/"
echo "    Log:            $LOG_FILE"
echo ""
echo "  Rollback: git reset --hard $CHECKPOINT_SHA"
echo ""
show_progress

# ─── Log pipeline completion summary to spec ─────────────────────
TOTAL_DURATION=$((SECONDS - PIPELINE_START))
TOTAL_MINS=$((TOTAL_DURATION / 60))
TOTAL_SECS=$((TOTAL_DURATION % 60))
ensure_log_section
{
    printf "### Pipeline Complete\n"
    printf "- **Total duration:** %dm %ds\n" "$TOTAL_MINS" "$TOTAL_SECS"
    printf "- **Finished:** %s\n" "$(date "+%Y-%m-%d %H:%M")"
    printf "- **Rollback:** \`git reset --hard %s\`\n" "$CHECKPOINT_SHA"
    printf "\n"
} >> "$SPEC_FILE"

echo "  Your turn: review the diff, check the UI in browser,"
echo "  and decide whether to merge or iterate."
echo ""
