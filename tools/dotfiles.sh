#!/bin/bash
# meister dotfiles — push/pull configs across machines
set -euo pipefail

D="$HOME/dotfiles"
G='\033[0;32m' R='\033[0;31m' N='\033[0m'

# What to sync: dotfiles_path → system_path
LINKS=(
  "claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "claude/settings.json:$HOME/.claude/settings.json"
  "claude/skills:$HOME/.claude/skills"
  "claude/hooks:$HOME/.claude/hooks"
  "claude/commands:$HOME/.claude/commands"
  "claude/agents:$HOME/.claude/agents"
  "claude/statusline-command.sh:$HOME/.claude/statusline-command.sh"
  "claude/package.json:$HOME/.claude/package.json"
  "claude-plugins/installed_plugins.json:$HOME/.claude/plugins/installed_plugins.json"
  "agents/skills:$HOME/.agents/skills"
  "agents/.skill-lock.json:$HOME/.agents/.skill-lock.json"
  "gemini/GEMINI.md:$HOME/.gemini/GEMINI.md"
  "gemini/settings.json:$HOME/.gemini/settings.json"
  "codex/config.toml:$HOME/.codex/config.toml"
  "git/.gitconfig:$HOME/.gitconfig"
  "ssh/config:$HOME/.ssh/config"
  "zsh/.zshrc:$HOME/.zshrc"
  "ghostty/config:$HOME/.config/ghostty/config"
  "atuin/config.toml:$HOME/.config/atuin/config.toml"
)

pull() {
  [ -d "$D/.git" ] || { echo "Run: git clone git@github.com:YOUR/dotfiles.git ~/dotfiles"; exit 1; }
  cd "$D" && git pull --rebase 2>/dev/null || true

  for entry in "${LINKS[@]}"; do
    src="$D/${entry%%:*}" dst="${entry#*:}"
    [ -e "$src" ] || continue
    mkdir -p "$(dirname "$dst")"
    [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] && continue
    [ -e "$dst" ] && [ ! -L "$dst" ] && mv "$dst" "$dst.bak"
    ln -sf "$src" "$dst"
    echo -e "  ${G}→${N} $dst"
  done
  mkdir -p ~/.ssh/sockets
  echo "Done."
}

push() {
  [ -d "$D/.git" ] || { echo "No dotfiles repo."; exit 1; }
  cd "$D" && git add -A
  git diff --cached --quiet && git diff --quiet && [ -z "$(git ls-files --others --exclude-standard)" ] && { echo "Nothing changed."; return; }
  git commit -m "sync $(date +%Y-%m-%d\ %H:%M) from $(hostname -s)"
  git push
}

status() {
  local ok=0 bad=0
  for entry in "${LINKS[@]}"; do
    src="$D/${entry%%:*}" dst="${entry#*:}"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      ok=$((ok + 1))
    else
      echo -e "  ${R}✗${N} $dst"
      bad=$((bad + 1))
    fi
  done
  echo "$ok linked, $bad issues"
}

case "${1:-help}" in
  pull|d)   pull ;;
  push|u)   push ;;
  status|s) status ;;
  *) echo "meister push — collect + push"; echo "meister pull — pull + link"; echo "meister status — check" ;;
esac
