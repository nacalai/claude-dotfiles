#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/nacalai/claude-dotfiles.git"
REPO_DIR="$HOME/projects/claude-dotfiles"

echo "=== Claude Code Dotfiles Setup ==="

# 0. Clone the repo if running via curl (not from local checkout)
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Cloning dotfiles repo..."
  mkdir -p ~/projects
  git clone "$REPO_URL" "$REPO_DIR"
fi

# 1. Install Claude Code if missing
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code..."
  npm i -g @anthropic-ai/claude-code
else
  echo "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi

# 2. Ensure ~/.claude directories exist
mkdir -p ~/.claude/hooks
mkdir -p ~/.claude/projects/-home-sprite/memory

# 3. Copy settings (won't overwrite if already exists — use -f flag to force)
FORCE=false
[[ "${1:-}" == "-f" || "${1:-}" == "--force" ]] && FORCE=true

copy_if_needed() {
  local src="$1" dst="$2"
  if [ ! -f "$dst" ] || [ "$FORCE" = true ]; then
    cp "$src" "$dst"
    echo "  Copied: $dst"
  else
    echo "  Skipped (exists): $dst"
  fi
}

echo "Copying settings..."
copy_if_needed "$REPO_DIR/.claude/settings.json" "$HOME/.claude/settings.json"

echo "Copying hooks..."
copy_if_needed "$REPO_DIR/.claude/hooks/sprite-env-check.sh" "$HOME/.claude/hooks/sprite-env-check.sh"
chmod +x ~/.claude/hooks/sprite-env-check.sh

echo "Copying memory..."
for f in "$REPO_DIR"/.claude/memory/*.md; do
  copy_if_needed "$f" "$HOME/.claude/projects/-home-sprite/memory/$(basename "$f")"
done

# 4. GitHub CLI auth (if GH_TOKEN is set)
if command -v gh &>/dev/null; then
  if ! gh auth status &>/dev/null; then
    if [ -n "${GH_TOKEN:-}" ]; then
      echo "$GH_TOKEN" | gh auth login --with-token
      echo "GitHub CLI: authenticated via GH_TOKEN"
    else
      echo "GitHub CLI: not authenticated. Set GH_TOKEN or run 'gh auth login -p https -w'"
    fi
  else
    echo "GitHub CLI: already authenticated"
  fi
fi

# 5. Create ~/projects if missing
mkdir -p ~/projects
echo "Projects directory: ~/projects/"

# 6. Install plugins
echo "Installing plugins..."
PLUGINS=(
  frontend-design
  superpowers
  context7
  code-review
  code-simplifier
  feature-dev
  playwright
  ralph-loop
  commit-commands
  security-guidance
  claude-md-management
  supabase
  vercel
)

for plugin in "${PLUGINS[@]}"; do
  echo "  Installing $plugin..."
  claude plugins install "$plugin" 2>/dev/null || echo "  Warning: failed to install $plugin"
done

echo ""
echo "=== Setup complete ==="
echo "Run 'claude' to start."
