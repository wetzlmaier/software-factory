#!/usr/bin/env bash
# Startet einen Factory-Job: Repo holen, Branch auschecken, Antigravity CLI (agy) mit Playbook laufen lassen.
# Erwartet: REPO, ISSUE, BRANCH, WORKFLOW, GH_TOKEN und $FACTORY_WORK/prompt.md (vom Runner geschrieben).
# Funktioniert sowohl im Docker-Container (/work, /factory, /scenarios) als auch lokal über
# FACTORY_WORK, FACTORY_ROOT und SCENARIOS_DIR (ohne API-Key über lokalen Antigravity-Login).
set -euo pipefail

log() { echo "[factory] $*"; }

: "${REPO:?}" "${ISSUE:?}" "${BRANCH:?}"
MODEL="${MODEL:-inherit}"
export PHASE="${PHASE:-build}"   # check = prüfen, build = entwickeln, accept = unabhängige Abnahme
WORKFLOW="${WORKFLOW:-starter-kit}"

WORK_DIR="${FACTORY_WORK:-/work}"
FACTORY_ROOT="${FACTORY_ROOT:-/factory}"
SCENARIOS_DIR="${SCENARIOS_DIR:-/scenarios}"
export FACTORY_WORK="$WORK_DIR"
export FACTORY_ROOT

if [ -d "$FACTORY_ROOT/image/bin" ]; then
  export PATH="$FACTORY_ROOT/image/bin:$PATH"
fi

WORKFLOW_DIR="$FACTORY_ROOT/workflows/$WORKFLOW"

# Workflow-Skills als globale Antigravity-Skills bereitstellen
mkdir -p "$HOME/.gemini/config/skills"
if [ -d "$WORKFLOW_DIR/skills" ]; then
  cp -r "$WORKFLOW_DIR/skills/." "$HOME/.gemini/config/skills/"
fi

if [ -n "${GH_TOKEN:-}" ]; then
  gh auth setup-git >/dev/null 2>&1 || true
fi
GH_LOGIN=$(gh api user --jq .login)
GH_ID=$(gh api user --jq .id)

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
if [ ! -d repo/.git ]; then
  log "Klone $REPO"
  gh repo clone "$REPO" repo -- --quiet
fi
cd repo
git config user.name "$GH_LOGIN (Software Factory)"
git config user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"

git fetch --quiet origin
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git checkout --quiet -B "$BRANCH" "origin/$BRANCH"
  # Die Abnahme startet immer mit genau dem gepushten Stand, ohne Reste früherer Läufe
  if [ "$PHASE" = "accept" ]; then git reset --quiet --hard "origin/$BRANCH" && git clean -ffdxq; fi
else
  git checkout --quiet -B "$BRANCH" "origin/$DEFAULT_BRANCH"
fi

# Workflow-Skills zusätzlich im Ziel-Repo bereitstellen und über .git/info/exclude verbergen,
# damit `git status --porcelain` in factory-verify sauber bleibt.
if [ -d "$WORKFLOW_DIR/skills" ]; then
  mkdir -p .agents/skills
  cp -r "$WORKFLOW_DIR/skills/." .agents/skills/
  mkdir -p .git/info
  grep -qxF '.agents/' .git/info/exclude 2>/dev/null || echo '.agents/' >> .git/info/exclude
fi

# Abhängigkeiten installieren (zum Entwickeln und für die Abnahme nötig)
if [ "$PHASE" != "check" ] && [ -f .factory/setup.json ]; then
  INSTALL=$(jq -r '.install // empty' .factory/setup.json)
  if [ -n "$INSTALL" ]; then
    log "Setup: $INSTALL"
    bash -lc "$INSTALL" > "$WORK_DIR/setup.log" 2>&1 || log "Setup fehlgeschlagen (siehe $WORK_DIR/setup.log), der Agent kümmert sich"
  fi
fi

PLAYBOOK="$FACTORY_ROOT/playbook.md"
[ -f "$PLAYBOOK" ] || PLAYBOOK="$FACTORY_ROOT/playbooks/factory.md"

# Playbook und Prompt kombinieren und Container-Pfade auf die aktiven Verzeichnisse auflösen
RAW_COMBINED="$(cat "$PLAYBOOK")"$'\n\n'"$(cat "$WORK_DIR/prompt.md")"
RAW_COMBINED="${RAW_COMBINED//\/scenarios\//${SCENARIOS_DIR}/}"
RAW_COMBINED="${RAW_COMBINED//\/factory\//${FACTORY_ROOT}/}"
RAW_COMBINED="${RAW_COMBINED//\/work\//${WORK_DIR}/}"
printf '%s\n' "$RAW_COMBINED" > "$WORK_DIR/full-prompt.md"

MODEL_ARGS=()
if [ -n "${MODEL:-}" ] && [ "$MODEL" != "inherit" ]; then
  MODEL_ARGS=(--model "$MODEL")
fi

export FACTORY_DEFAULT_BRANCH="$DEFAULT_BRANCH"
log "Starte Antigravity CLI ($MODEL, Phase: $PHASE, Workflow: $WORKFLOW) für $REPO#$ISSUE auf $BRANCH"
set +e
agy -p "$(cat "$WORK_DIR/full-prompt.md")" \
  --add-dir "$WORKFLOW_DIR" \
  --dangerously-skip-permissions \
  --mode auto \
  --output-format stream-json \
  "${MODEL_ARGS[@]}" \
  > "$WORK_DIR/agy.jsonl" 2> "$WORK_DIR/agy.err"
CODE=$?
set -e
log "Antigravity CLI beendet mit Exit-Code $CODE"
tail -n 1 "$WORK_DIR/agy.jsonl" | jq -r '"Ergebnis: " + ((.result // .text // .content // "-") | tostring | .[0:500])' 2>/dev/null || true
exit $CODE
