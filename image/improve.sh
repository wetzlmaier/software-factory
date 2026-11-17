#!/usr/bin/env bash
# Verbesserungs-Lauf: wertet die bisherigen Läufe aus und schlägt Änderungen am Playbook vor.
# Erwartet: REPO (Factory-Repo), GH_TOKEN, GEMINI_API_KEY (oder GOOGLE_API_KEY / ~/.gemini/antigravity-cli), MODEL
# Daten unter /data (nur lesend), Arbeitsordner /work.
set -euo pipefail
: "${REPO:?}"
MODEL="${MODEL:-inherit}"
export PHASE=improve

# Headless-Authentifizierung via Gemini API-Key konfigurieren (falls gesetzt)
if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
  export GEMINI_API_KEY="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
  mkdir -p "$HOME/.gemini/antigravity-cli"
  printf '{"modelProvider":"gemini"}\n' > "$HOME/.gemini/antigravity-cli/settings.json"
fi

gh auth setup-git >/dev/null
GH_LOGIN=$(gh api user --jq .login); GH_ID=$(gh api user --jq .id)
git config --global user.name "$GH_LOGIN (Software Factory)"
git config --global user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"

rm -rf /work/repo
gh repo clone "$REPO" /work/repo -- --quiet
cd /work/repo
DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
BRANCH="improve/$(date +%Y-%m-%d-%H%M)"
git checkout --quiet -b "$BRANCH"
export FACTORY_DEFAULT_BRANCH="$DEFAULT_BRANCH" FACTORY_METRICS=/data/metrics.jsonl

PLAYBOOK=/work/repo/playbooks/improve.md
[ -f "$PLAYBOOK" ] || PLAYBOOK=/factory/improve.md

RUNS=$(ls /data/runs 2>/dev/null | wc -l)
LINES=$(wc -l < /data/metrics.jsonl 2>/dev/null || echo 0)
echo "[improve] $LINES Läufe in den Metriken, $RUNS Zusammenfassungen, Branch $BRANCH"

PROMPT_BODY="Werte die bisherigen Läufe der Software Factory aus und schlage Verbesserungen vor, wie im Verbesserungs-Playbook beschrieben. Factory-Repo: $REPO (geklont unter /work/repo, Branch $BRANCH, Standard-Branch $DEFAULT_BRANCH). Daten: /data/metrics.jsonl ($LINES Läufe) und /data/runs ($RUNS Zusammenfassungen)."
printf '%s\n\n%s\n' "$(cat "$PLAYBOOK")" "$PROMPT_BODY" > /work/full-prompt.md

MODEL_ARGS=()
if [ -n "${MODEL:-}" ] && [ "$MODEL" != "inherit" ]; then
  MODEL_ARGS=(--model "$MODEL")
fi

set +e
agy -p "$(cat /work/full-prompt.md)" \
  --dangerously-skip-permissions \
  --mode auto \
  --output-format stream-json \
  "${MODEL_ARGS[@]}" \
  > /work/agy.jsonl 2> /work/agy.err
CODE=$?
set -e
tail -n 1 /work/agy.jsonl | jq -r '"Ergebnis: " + ((.result // .text // .content // "-") | tostring | .[0:800])' 2>/dev/null || true
exit $CODE
