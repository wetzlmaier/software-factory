#!/usr/bin/env bash
# Startet einen Factory-Job: Repo holen, Branch auschecken, Antigravity CLI (agy) mit Playbook laufen lassen.
# Erwartet: REPO, ISSUE, BRANCH, MODEL, WORKFLOW, GH_TOKEN, GEMINI_API_KEY (oder GOOGLE_API_KEY / ~/.gemini/antigravity-cli)
# und /work/prompt.md (vom Runner geschrieben).
set -euo pipefail

log() { echo "[factory] $*"; }

: "${REPO:?}" "${ISSUE:?}" "${BRANCH:?}"
MODEL="${MODEL:-inherit}"
export PHASE="${PHASE:-build}"   # check = prüfen, build = entwickeln, accept = unabhängige Abnahme
WORKFLOW="${WORKFLOW:-starter-kit}"

# Workflow-Skills als Nutzer-Skills für Antigravity bereitstellen (landen nicht im Ziel-Repo)
mkdir -p "$HOME/.gemini/config/skills"
if [ -d "/factory/workflows/$WORKFLOW/skills" ]; then
  cp -r "/factory/workflows/$WORKFLOW/skills/." "$HOME/.gemini/config/skills/"
fi

# Headless-Authentifizierung via Gemini API-Key konfigurieren (falls gesetzt)
if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
  export GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
  mkdir -p "$HOME/.gemini/antigravity-cli"
  printf '{"modelProvider":"gemini"}\n' > "$HOME/.gemini/antigravity-cli/settings.json"
fi

gh auth setup-git >/dev/null
GH_LOGIN=$(gh api user --jq .login)
GH_ID=$(gh api user --jq .id)
git config --global user.name "$GH_LOGIN (Software Factory)"
git config --global user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"
git config --global init.defaultBranch main

cd /work
if [ ! -d repo/.git ]; then
  log "Klone $REPO"
  gh repo clone "$REPO" repo -- --quiet
fi
cd repo
git fetch --quiet origin
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git checkout --quiet -B "$BRANCH" "origin/$BRANCH"
  # Die Abnahme startet immer mit genau dem gepushten Stand, ohne Reste früherer Läufe
  if [ "$PHASE" = "accept" ]; then git reset --quiet --hard "origin/$BRANCH" && git clean -ffdxq; fi
else
  git checkout --quiet -B "$BRANCH" "origin/$DEFAULT_BRANCH"
fi

# Workflow-Skills zusätzlich im Ziel-Repo bereitstellen und über .git/info/exclude ausblenden,
# damit `git status --porcelain` in factory-verify sauber bleibt
if [ -d "/factory/workflows/$WORKFLOW/skills" ]; then
  mkdir -p .agents/skills
  cp -r "/factory/workflows/$WORKFLOW/skills/." .agents/skills/
  mkdir -p .git/info
  grep -qxF '.agents/' .git/info/exclude 2>/dev/null || echo '.agents/' >> .git/info/exclude
fi

# Abhängigkeiten installieren (zum Entwickeln und für die Abnahme nötig)
if [ "$PHASE" != "check" ] && [ -f .factory/setup.json ]; then
  INSTALL=$(jq -r '.install // empty' .factory/setup.json)
  if [ -n "$INSTALL" ]; then
    log "Setup: $INSTALL"
    bash -lc "$INSTALL" > /work/setup.log 2>&1 || log "Setup fehlgeschlagen (siehe /work/setup.log), der Agent kümmert sich"
  fi
fi

printf '%s\n\n%s\n' "$(cat /factory/playbook.md)" "$(cat /work/prompt.md)" > /work/full-prompt.md

MODEL_ARGS=()
if [ -n "${MODEL:-}" ] && [ "$MODEL" != "inherit" ]; then
  MODEL_ARGS=(--model "$MODEL")
fi

export FACTORY_DEFAULT_BRANCH="$DEFAULT_BRANCH"
log "Starte Antigravity CLI ($MODEL, Phase: $PHASE, Workflow: $WORKFLOW) für $REPO#$ISSUE auf $BRANCH"
set +e
agy -p "$(cat /work/full-prompt.md)" \
  --add-dir "/factory/workflows/$WORKFLOW" \
  --dangerously-skip-permissions \
  --mode auto \
  --output-format stream-json \
  "${MODEL_ARGS[@]}" \
  > /work/agy.jsonl 2> /work/agy.err
CODE=$?
set -e
log "Antigravity CLI beendet mit Exit-Code $CODE"
tail -n 1 /work/agy.jsonl | jq -r '"Ergebnis: " + ((.result // .text // .content // "-") | tostring | .[0:500])' 2>/dev/null || true
exit $CODE
