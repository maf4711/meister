#!/bin/bash
# meister dotfiles — one command to rule them all
set -euo pipefail

D="$HOME/dotfiles"
G='\033[0;32m' R='\033[0;31m' Y='\033[0;33m' N='\033[0m'
KEY="$HOME/.ssh/id_ed25519_github"
REPO="maf4711/dotfiles"

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

ensure_brew() {
  command -v brew &>/dev/null && return
  echo "  Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

ensure_gh() {
  command -v gh &>/dev/null && return
  echo "  Installing gh..."
  brew install gh
}

ensure_ssh_key() {
  [ -f "$KEY" ] && return
  echo "  Generating SSH key..."
  mkdir -p ~/.ssh/sockets
  ssh-keygen -t ed25519 -C "marco@merados.com" -f "$KEY" -N ""
}

ensure_gh_auth() {
  if ! gh auth status &>/dev/null; then
    echo "  Logging into GitHub..."
    gh auth login -p ssh -h github.com -s admin:public_key,admin:ssh_signing_key,delete_repo,gist,read:gpg_key,read:org,repo,user,workflow
  else
    local scopes
    scopes=$(gh auth status 2>&1 | grep "Token scopes" || true)
    if ! echo "$scopes" | grep -q "admin:ssh_signing_key"; then
      gh auth refresh -h github.com -s admin:ssh_signing_key,user,read:gpg_key
    fi
  fi
}

ensure_gh_keys() {
  local pubkey existing signing_keys
  pubkey=$(awk '{print $2}' "$KEY.pub")
  existing=$(gh ssh-key list 2>/dev/null || true)

  echo "$existing" | grep -q "$pubkey" || \
    gh ssh-key add "$KEY.pub" --type authentication --title "$(hostname -s)"

  signing_keys=$(echo "$existing" | grep signing || true)
  echo "$signing_keys" | grep -q "$pubkey" || \
    gh ssh-key add "$KEY.pub" --type signing --title "$(hostname -s) signing"
}

ensure_repo() {
  [ -d "$D/.git" ] && return
  echo "  Cloning dotfiles..."
  git clone "git@github.com:$REPO.git" "$D"
}

link_all() {
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
  [ -f "$KEY.pub" ] && echo "marco@merados.com $(cat "$KEY.pub")" > "$HOME/.ssh/allowed_signers"
}

setup() {
  echo -e "${Y}Setting up $(hostname -s)...${N}"
  ensure_brew
  ensure_gh
  ensure_ssh_key
  ensure_gh_auth
  ensure_gh_keys
  ensure_repo
  cd "$D" && git pull --rebase 2>/dev/null || true
  link_all
  echo -e "${G}Done.${N}"
}

pull() {
  [ -d "$D/.git" ] || { echo "Run: meister setup"; exit 1; }
  cd "$D" && git pull --rebase 2>/dev/null || true
  link_all
}

push() {
  [ -d "$D/.git" ] || { echo "Run: meister setup"; exit 1; }
  cd "$D" && git add -A
  git diff --cached --quiet && git diff --quiet && [ -z "$(git ls-files --others --exclude-standard)" ] && { echo "Nothing changed."; return; }
  git commit -m "sync $(date +%Y-%m-%d\ %H:%M) from $(hostname -s)"
  git push
}

status() {
  local ok=0 bad=0
  for entry in "${LINKS[@]}"; do
    src="$D/${entry%%:*}" dst="${entry#*:}"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then ok=$((ok + 1))
    else echo -e "  ${R}✗${N} $dst"; bad=$((bad + 1)); fi
  done
  echo "$ok linked, $bad issues"
  [ -f "$KEY" ] && echo -e "  ${G}✓${N} SSH key" || echo -e "  ${R}✗${N} SSH key missing"
  gh auth status &>/dev/null && echo -e "  ${G}✓${N} gh auth" || echo -e "  ${R}✗${N} gh auth"
}

case "${1:-help}" in
  setup)    setup ;;
  pull|d)   pull ;;
  push|u)   push ;;
  status|s) status ;;
  *) echo "meister setup  — new Mac, one command"; echo "meister pull   — pull + link"; echo "meister push   — collect + push"; echo "meister status — check" ;;
esac
