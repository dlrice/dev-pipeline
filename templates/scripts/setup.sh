#!/bin/bash
set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# ─── Install CLI agents ─────────────────────────────────────────
echo ""
echo "Installing CLI agents..."

if command -v claude &> /dev/null; then
    echo -e "${GREEN}✓${NC} Claude Code already installed"
else
    echo "  Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    echo -e "${GREEN}✓${NC} Claude Code installed"
fi

if command -v gemini &> /dev/null; then
    echo -e "${GREEN}✓${NC} Gemini CLI already installed"
else
    echo "  Installing Gemini CLI..."
    npm install -g @google/gemini-cli
    echo -e "${GREEN}✓${NC} Gemini CLI installed"
fi

if command -v qwen &> /dev/null; then
    echo -e "${GREEN}✓${NC} Qwen Code already installed"
else
    echo "  Installing Qwen Code..."
    curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh | bash
    echo -e "${GREEN}✓${NC} Qwen Code installed"
fi

# ─── Create directory structure (idempotent) ─────────────────────
echo ""
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
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
echo -e "${GREEN}✓${NC} Directory structure ready"

# ─── Create stub files (do NOT overwrite existing) ───────────────
echo "Checking stub files..."

declare -A STUBS=(
    ["specs/_template.md"]="exists"
    ["CLAUDE.md"]="exists"
    ["GEMINI.md"]="exists"
    ["AGENTS.md"]="exists"
    ["pipeline.config.json"]="exists"
    ["docs/ARCHITECTURE.md"]="exists"
    ["docs/CONVENTIONS.md"]="exists"
    ["docs/DATA-MODEL.md"]="exists"
    ["docs/DEPENDENCIES.md"]="exists"
    ["docs/DECISIONS.md"]="exists"
)

ALL_EXIST=true
for file in "${!STUBS[@]}"; do
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

# ─── Done ────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""
echo "  Next steps — authenticate each tool once:"
echo ""
echo "    1. Run ${GREEN}claude${NC} and sign in with your Claude Pro account"
echo "    2. Run ${GREEN}gemini${NC} and sign in with your Google account"
echo "    3. Run ${GREEN}qwen${NC}  and sign in with your Qwen account (create at qwen.ai)"
echo ""
echo "  All three are cloud-based. No local models, no API keys."
echo ""
echo "  To start the pipeline on a feature:"
echo "    cp specs/_template.md specs/my-feature.md"
echo "    # Edit specs/my-feature.md"
echo "    ./scripts/dev-loop.sh my-feature"
echo ""
