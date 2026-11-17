#!/usr/bin/env bash
# Installiert die Factory-Skills (init, write-spec, to-factory, run-factory sowie
# architecture, build, qa) einmalig global für Antigravity (~/.gemini/config/skills).
# Existiert ~/.claude, werden die Skills dort ebenfalls verlinkt.
# Updates: im Factory-Repo "git pull", fertig (es sind Verknüpfungen).
#   ./scripts/install-local-skills.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES=("$ROOT/local-skills" "$ROOT/workflows/starter-kit/skills")

link_skills() {
  local dest="$1"
  mkdir -p "$dest"
  for src in "${SOURCES[@]}"; do
    [ -d "$src" ] || continue
    for skill in "$src"/*/; do
      [ -d "$skill" ] || continue
      local name
      name=$(basename "$skill")
      if [ -e "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
        mv "$dest/$name" "$dest/$name.backup-$(date +%Y%m%d%H%M%S)"
        echo "  vorhandenen Skill '$name' in $dest gesichert"
      fi
      ln -sfn "${skill%/}" "$dest/$name"
      echo "  ✓ $dest/$name"
    done
  done
}

echo "▶ Installiere Factory-Skills für Antigravity ($HOME/.gemini/config/skills):"
link_skills "$HOME/.gemini/config/skills"

if [ -d "$HOME/.claude" ]; then
  echo "▶ Verlinke Factory-Skills zusätzlich für Claude ($HOME/.claude/skills):"
  link_skills "$HOME/.claude/skills"
fi

echo "Fertig. Die Skills stehen in jedem Antigravity-Projekt zur Verfügung."
