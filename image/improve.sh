#!/usr/bin/env bash
# Verbesserungs-Lauf: wertet die bisherigen Läufe aus und schlägt Änderungen am Playbook vor.
# Erwartet: REPO (Factory-Repo), GH_TOKEN, optional MODEL.
# Funktioniert im Container (/data, /work, /factory) und lokal über FACTORY_DATA, FACTORY_WORK, FACTORY_ROOT.
set -euo pipefail
: "${REPO:?}"
MODEL="${MODEL:-inherit}"
export PHASE=improve

WORK_DIR="${FACTORY_WORK:-/work}"
FACTORY_ROOT="${FACTORY_ROOT:-/factory}"
DATA_DIR="${FACTORY_DATA:-/data}"
export FACTORY_WORK="$WORK_DIR"
export FACTORY_ROOT

if [ -n "${GH_TOKEN:-}" ]; then
  gh auth setup-git >/dev/null 2>&1 || true
fi
GH_LOGIN=$(gh api user --jq .login); GH_ID=$(gh api user --jq .id)

mkdir -p "$WORK_DIR"
rm -rf "$WORK_DIR/repo"
gh repo clone "$REPO" "$WORK_DIR/repo" -- --quiet
cd "$WORK_DIR/repo"
git config user.name "$GH_LOGIN (Software Factory)"
git config user.email "${GH_ID}+${GH_LOGIN}@users.noreply.github.com"

DEFAULT_BRANCH=$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
BRANCH="improve/$(date +%Y-%m-%d-%H%M)"
git checkout --quiet -b "$BRANCH"
export FACTORY_DEFAULT_BRANCH="$DEFAULT_BRANCH" FACTORY_METRICS="$DATA_DIR/metrics.jsonl"

PLAYBOOK="$WORK_DIR/repo/playbooks/improve.md"
[ -f "$PLAYBOOK" ] || PLAYBOOK="$FACTORY_ROOT/improve.md"
[ -f "$PLAYBOOK" ] || PLAYBOOK="$FACTORY_ROOT/playbooks/improve.md"

RUNS=$(ls "$DATA_DIR/runs" 2>/dev/null | wc -l)
LINES=$(wc -l < "$DATA_DIR/metrics.jsonl" 2>/dev/null || echo 0)
echo "[improve] $LINES Läufe in den Metriken, $RUNS Zusammenfassungen, Branch $BRANCH"

PROMPT_BODY="Werte die bisherigen Läufe der Software Factory aus und schlage Verbesserungen vor, wie im Verbesserungs-Playbook beschrieben. Factory-Repo: $REPO (geklont unter $WORK_DIR/repo, Branch $BRANCH, Standard-Branch $DEFAULT_BRANCH). Daten: $DATA_DIR/metrics.jsonl ($LINES Läufe) und $DATA_DIR/runs ($RUNS Zusammenfassungen)."
RAW_COMBINED="$(cat "$PLAYBOOK")"$'\n\n'"$PROMPT_BODY"
RAW_COMBINED="${RAW_COMBINED//\/data\//${DATA_DIR}/}"
RAW_COMBINED="${RAW_COMBINED//\/work\//${WORK_DIR}/}"
printf '%s\n' "$RAW_COMBINED" > "$WORK_DIR/full-prompt.md"

MODEL_ARGS=()
if [ -n "${MODEL:-}" ] && [ "$MODEL" != "inherit" ]; then
  MODEL_ARGS=(--model "$MODEL")
fi

set +e
agy -p "$(cat "$WORK_DIR/full-prompt.md")" \
  --dangerously-skip-permissions \
  --mode auto \
  --output-format stream-json \
  "${MODEL_ARGS[@]}" \
  > "$WORK_DIR/agy.jsonl" 2> "$WORK_DIR/agy.err"
CODE=$?
set -e
tail -n 1 "$WORK_DIR/agy.jsonl" | jq -r '"Ergebnis: " + ((.result // .text // .content // "-") | tostring | .[0:800])' 2>/dev/null || true
exit $CODE
