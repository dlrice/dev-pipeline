#!/bin/bash
set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "  Spec-Driven Pipeline — Setup"
echo "=========================================="
echo ""

# ─── Check prerequisites ────────────────────────────────────────
echo "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found.${NC} Install v18+: https://nodejs.org"
    exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo -e "${RED}✗ Node.js v18+ required.${NC} Found: $(node -v)"
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js $(node -v)"

if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Git not found.${NC} Install: https://git-scm.com"
    exit 1
fi
echo -e "${GREEN}✓${NC} Git $(git --version | cut -d' ' -f3)"

if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗ npm not found.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} npm $(npm -v)"


# ═════════════════════════════════════════════════════════════════
# Install CLI agents
# ═════════════════════════════════════════════════════════════════
echo ""
echo "Installing CLI agents..."
echo ""

# ─── Claude Code ─────────────────────────────────────────────────
# Docs: https://code.claude.com/docs/en/setup
# Requires: Claude Pro, Max, Teams, or Enterprise account ($20/mo+)
# Auth: OAuth browser login on first run
echo -e "${BOLD}1. Claude Code${NC}"
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    echo -e "   ${GREEN}✓${NC} Already installed (${CLAUDE_VERSION})"
else
    echo "   Installing Claude Code..."
    # Prefer the official installer (avoids npm permission issues)
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} Claude Code installed via official installer"
    else
        # Fallback to npm
        echo "   Official installer failed, trying npm..."
        npm install -g @anthropic-ai/claude-code
        echo -e "   ${GREEN}✓${NC} Claude Code installed via npm"
    fi
fi
echo ""

# ─── Gemini CLI ──────────────────────────────────────────────────
# Docs: https://github.com/google-gemini/gemini-cli
# Requires: Google account (free tier: 60 req/min, 1000 req/day)
# Auth: OAuth browser login on first run
echo -e "${BOLD}2. Gemini CLI${NC}"
if command -v gemini &> /dev/null; then
    GEMINI_VERSION=$(gemini --version 2>/dev/null || echo "unknown")
    echo -e "   ${GREEN}✓${NC} Already installed (${GEMINI_VERSION})"
else
    echo "   Installing Gemini CLI..."
    npm install -g @google/gemini-cli
    echo -e "   ${GREEN}✓${NC} Gemini CLI installed"
fi
echo ""

# ─── Qwen Code ───────────────────────────────────────────────────
# Docs: https://github.com/QwenLM/qwen-code
# Requires: Qwen account (free at qwen.ai) or API key
# Auth: OAuth browser login on first interactive run
echo -e "${BOLD}3. Qwen Code${NC}"
if command -v qwen &> /dev/null; then
    QWEN_VERSION=$(qwen --version 2>/dev/null || echo "unknown")
    echo -e "   ${GREEN}✓${NC} Already installed (${QWEN_VERSION})"
else
    echo "   Installing Qwen Code..."
    npm install -g @qwen-code/qwen-code
    if command -v qwen &> /dev/null; then
        echo -e "   ${GREEN}✓${NC} Qwen Code installed via npm"
    else
        echo "   npm install didn't add qwen to PATH, trying official installer..."
        curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh | bash 2>/dev/null || true
        if command -v qwen &> /dev/null; then
            echo -e "   ${GREEN}✓${NC} Qwen Code installed via official installer"
        else
            echo -e "   ${YELLOW}⚠${NC} Qwen Code installed but not on PATH."
            echo "     You may need to restart your terminal or add it to your PATH."
            echo "     Check: https://github.com/QwenLM/qwen-code#installation"
        fi
    fi
fi
echo ""


# ═════════════════════════════════════════════════════════════════
# Verify authentication status
# ═════════════════════════════════════════════════════════════════
echo "──────────────────────────────────────────"
echo "  Checking authentication status..."
echo "──────────────────────────────────────────"
echo ""

AUTH_ISSUES=0

# Claude auth check
if command -v claude &> /dev/null; then
    # claude -p with a trivial prompt will fail if not authenticated
    if claude -p "echo hello" --max-turns 1 > /dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} Claude Code: authenticated"
    else
        echo -e "   ${YELLOW}⚠${NC} Claude Code: not authenticated"
        AUTH_ISSUES=$((AUTH_ISSUES + 1))
    fi
else
    echo -e "   ${RED}✗${NC} Claude Code: not installed"
    AUTH_ISSUES=$((AUTH_ISSUES + 1))
fi

# Gemini auth check
if command -v gemini &> /dev/null; then
    if gemini -p "echo hello" --sandbox > /dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} Gemini CLI: authenticated"
    else
        echo -e "   ${YELLOW}⚠${NC} Gemini CLI: not authenticated"
        AUTH_ISSUES=$((AUTH_ISSUES + 1))
    fi
else
    echo -e "   ${RED}✗${NC} Gemini CLI: not installed"
    AUTH_ISSUES=$((AUTH_ISSUES + 1))
fi

# Qwen auth check
if command -v qwen &> /dev/null; then
    if qwen -p "echo hello" --max-turns 1 > /dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} Qwen Code: authenticated"
    else
        echo -e "   ${YELLOW}⚠${NC} Qwen Code: not authenticated"
        AUTH_ISSUES=$((AUTH_ISSUES + 1))
    fi
else
    echo -e "   ${RED}✗${NC} Qwen Code: not installed"
    AUTH_ISSUES=$((AUTH_ISSUES + 1))
fi

echo ""

# ─── Create directory structure (idempotent) ─────────────────────
echo "Ensuring directory structure..."

DIRS=(
    "specs"
    "plans"
    "reviews/spec-critiques"
    "reviews/plan-reviews"
    "reviews/adversarial"
    "tests/gemini"
    "tests/qwen"
    "tests/adversarial"
    "tests/merged"
    "docs"
    "scripts"
    "logs"
    "src"
    ".pipeline"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
echo -e "${GREEN}✓${NC} Directory structure ready"

# ─── Create stub files (do NOT overwrite existing) ───────────────
echo "Checking stub files..."

STUB_FILES=(
    "specs/_template.md"
    "CLAUDE.md"
    "GEMINI.md"
    "AGENTS.md"
    "pipeline.config.json"
    "docs/ARCHITECTURE.md"
    "docs/CONVENTIONS.md"
    "docs/DATA-MODEL.md"
    "docs/DEPENDENCIES.md"
    "docs/DECISIONS.md"
)

ALL_EXIST=true
for file in "${STUB_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        ALL_EXIST=false
        echo -e "${YELLOW}!${NC} Missing: $file (should be in repo)"
    fi
done

if [ "$ALL_EXIST" = true ]; then
    echo -e "${GREEN}✓${NC} All stub files present"
fi

# ─── Bootstrap docs from existing codebase ───────────────────────
if [ "${1:-}" = "--bootstrap" ]; then
    echo ""
    echo "Bootstrapping documentation from codebase..."
    echo -e "${YELLOW}Warning:${NC} This will overwrite files in docs/."
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  Running Claude Code to generate ARCHITECTURE.md and DATA-MODEL.md..."
        claude -p "Scan this entire codebase. Read every file in src/, tests/, and config files. Generate docs/ARCHITECTURE.md and docs/DATA-MODEL.md as described in CLAUDE.md." --dangerously-skip-permissions || true

        echo "  Running Gemini CLI to generate CONVENTIONS.md..."
        gemini -p "Read every file in src/ and tests/. Generate docs/CONVENTIONS.md by inferring conventions actually in use." --yolo || true

        echo "  Running Claude Code to generate DEPENDENCIES.md..."
        claude -p "Read package.json. Generate docs/DEPENDENCIES.md listing every non-trivial dependency with what it does and where it is used." --dangerously-skip-permissions || true

        echo "  Running Claude Code to generate DECISIONS.md skeleton..."
        claude -p "Scan the codebase and infer architectural decisions. Generate docs/DECISIONS.md with the decision and alternatives. Leave Reasoning fields for the developer to fill in." --dangerously-skip-permissions || true

        echo ""
        echo -e "${GREEN}✓${NC} Bootstrap complete. Review and correct all files in docs/."
    fi
fi


# ═════════════════════════════════════════════════════════════════
# Done — show authentication instructions if needed
# ═════════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""

if [ "$AUTH_ISSUES" -gt 0 ]; then
    echo -e "  ${YELLOW}$AUTH_ISSUES tool(s) need authentication.${NC}"
    echo "  Run each tool interactively once to complete login:"
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │                                                              │"
    echo -e "  │  ${BOLD}Claude Code${NC}                                                │"
    echo "  │  Requires: Claude Pro, Max, Teams, or Enterprise account     │"
    echo -e "  │  Run: ${GREEN}claude${NC}                                                  │"
    echo "  │  → Opens browser for Anthropic OAuth login                   │"
    echo "  │  → Credentials are cached locally after first login          │"
    echo "  │                                                              │"
    echo -e "  │  ${BOLD}Gemini CLI${NC}                                                  │"
    echo "  │  Requires: Google account (free tier: 60 req/min)            │"
    echo -e "  │  Run: ${GREEN}gemini${NC}                                                  │"
    echo "  │  → Opens browser for Google OAuth login                      │"
    echo "  │  → Credentials are cached locally after first login          │"
    echo "  │                                                              │"
    echo -e "  │  ${BOLD}Qwen Code${NC}                                                   │"
    echo "  │  Requires: Qwen account (free — create at qwen.ai)          │"
    echo -e "  │  Run: ${GREEN}qwen${NC}                                                    │"
    echo "  │  → Opens browser for Qwen OAuth login                        │"
    echo "  │  → Credentials are cached locally after first login          │"
    echo "  │                                                              │"
    echo "  │  All three use OAuth — no API keys or tokens to manage.      │"
    echo "  │  Each login only needs to happen once per machine.           │"
    echo "  │                                                              │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  After authenticating, verify with:"
    echo -e "    ${GREEN}npx dev-pipeline doctor${NC}"
    echo ""
else
    echo -e "  ${GREEN}All tools installed and authenticated!${NC}"
    echo ""
fi

echo "  To start the pipeline on a feature:"
echo "    cp specs/_template.md specs/my-feature.md"
echo "    # Edit specs/my-feature.md"
echo -e "    ${GREEN}./scripts/dev-loop.sh my-feature${NC}"
echo ""
