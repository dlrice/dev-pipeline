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
echo "  aidev — Setup"
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
echo -e "${BOLD}1. Claude Code${NC}"
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    echo -e "   ${GREEN}✓${NC} Already installed (${CLAUDE_VERSION})"
else
    echo "   Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} Claude Code installed via official installer"
    else
        echo "   Official installer failed, trying npm..."
        npm install -g @anthropic-ai/claude-code
        echo -e "   ${GREEN}✓${NC} Claude Code installed via npm"
    fi
fi
echo ""

# ─── Gemini CLI ──────────────────────────────────────────────────
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
        fi
    fi
fi
echo ""


# ═════════════════════════════════════════════════════════════════
# Verify authentication status (Best Practices)
# ═════════════════════════════════════════════════════════════════
echo "──────────────────────────────────────────"
echo "  Checking authentication status..."
echo "──────────────────────────────────────────"
echo ""

AUTH_ISSUES=0

# ─── Claude Code auth ────────────────────────────────────────────
# Best practice: Claude Code has a dedicated, non-interactive command
# `claude auth status` that exits 0 if authenticated, 1 if not.
if command -v claude &> /dev/null; then
    CLAUDE_AUTHED=false

    if claude auth status >/dev/null 2>&1; then
        CLAUDE_AUTHED=true
    # Fallback to checking the environment variable (highest priority in non-interactive mode)
    elif [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        CLAUDE_AUTHED=true
    fi

    if [ "$CLAUDE_AUTHED" = true ]; then
        echo -e "   ${GREEN}✓${NC} Claude Code: authenticated"
    else
        echo -e "   ${YELLOW}⚠${NC} Claude Code: not authenticated"
        AUTH_ISSUES=$((AUTH_ISSUES + 1))
    fi
else
    echo -e "   ${RED}✗${NC} Claude Code: not installed"
    AUTH_ISSUES=$((AUTH_ISSUES + 1))
fi

# ─── Gemini CLI auth ─────────────────────────────────────────────
# Best practice: Gemini CLI relies heavily on GCP ADC or explicit API keys. 
# We check standard env vars first, then ADC, then local cached settings.
if command -v gemini &> /dev/null; then
    GEMINI_AUTHED=false

    # 1. Check for standard Environment Variables
    if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
        GEMINI_AUTHED=true
    # 2. Check for Application Default Credentials (GCP)
    elif [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
        GEMINI_AUTHED=true
    # 3. Check for settings file (created after successful OAuth via `gemini /auth`)
    elif [ -f "$HOME/.gemini/settings.json" ]; then
        GEMINI_AUTHED=true
    fi

    if [ "$GEMINI_AUTHED" = true ]; then
        echo -e "   ${GREEN}✓${NC} Gemini CLI: authenticated"
    else
        echo -e "   ${YELLOW}⚠${NC} Gemini CLI: not authenticated"
        AUTH_ISSUES=$((AUTH_ISSUES + 1))
    fi
else
    echo -e "   ${RED}✗${NC} Gemini CLI: not installed"
    AUTH_ISSUES=$((AUTH_ISSUES + 1))
fi

# ─── Qwen Code auth ──────────────────────────────────────────────
# Best practice: Qwen Code uses OAuth by default (saving to oauth_creds.json),
# or standard OpenAI-compatible API keys set via settings.json or Env Vars.
if command -v qwen &> /dev/null; then
    QWEN_AUTHED=false

    # 1. Check for Qwen OAuth credentials (recommended free tier)
    if [ -f "$HOME/.qwen/oauth_creds.json" ]; then
        QWEN_AUTHED=true
    # 2. Check settings.json for an explicit auth type selection
    elif [ -f "$HOME/.qwen/settings.json" ] && grep -q '"selectedType"' "$HOME/.qwen/settings.json" 2>/dev/null; then
        QWEN_AUTHED=true
    # 3. Fallback: check standard environment variables
    elif [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${DASHSCOPE_API_KEY:-}" ]; then
        QWEN_AUTHED=true
    fi

    if [ "$QWEN_AUTHED" = true ]; then
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

# ─── Check for aidev config ──────────────────────────────────────
if [ -f "aidev.config.json" ]; then
    echo -e "${GREEN}✓${NC} aidev.config.json found"
else
    echo -e "${YELLOW}!${NC} aidev.config.json not found. Run 'aidev init' first."
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
    echo -e "  │  ${BOLD}Claude Code${NC}                                               │"
    echo "  │  Requires: Claude Pro, Max, Teams, or Enterprise account     │"
    echo -e "  │  Run: ${GREEN}claude auth login${NC}                                      │"
    echo "  │  → Opens browser for Anthropic OAuth login                   │"
    echo "  │                                                              │"
    echo -e "  │  ${BOLD}Gemini CLI${NC}                                                │"
    echo "  │  Requires: Google account (free tier: 60 req/min)            │"
    echo -e "  │  Run: ${GREEN}gemini${NC}                                                │"
    echo "  │  → Opens browser for Google OAuth login                      │"
    echo "  │                                                              │"
    echo -e "  │  ${BOLD}Qwen Code${NC}                                                 │"
    echo "  │  Requires: Qwen account (free tier: 2,000 req/day)           │"
    echo -e "  │  Run: ${GREEN}qwen${NC} (Then type ${GREEN}/auth${NC})                              │"
    echo "  │  → Select 'Qwen OAuth' to open browser login                 │"
    echo "  │                                                              │"
    echo "  │  All three use OAuth — no API keys or tokens to manage.      │"
    echo "  │  Each login only needs to happen once per machine.           │"
    echo "  │                                                              │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  After authenticating, verify with:"
    echo -e "    ${GREEN}aidev doctor${NC}"
    echo ""
else
    echo -e "  ${GREEN}All tools installed and authenticated!${NC}"
    echo ""
fi

echo "  To start the pipeline on a feature:"
echo "    cp aidev/specs/_template.md aidev/specs/my-feature.md"
echo "    # Edit aidev/specs/my-feature.md"
echo -e "    ${GREEN}aidev run my-feature${NC}"
echo ""