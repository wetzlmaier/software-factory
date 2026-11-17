# Software Factory (Antigravity Edition)

Dieses Repository enthält eine automatisierte dreiphasige Software Factory (**Prüfung → Bau → Unabhängige Abnahme**), angepasst für Google Antigravity ohne API-Key-Zwang.

## Architektur & Betriebsarten (ohne API-Key)

1. **Direkt in Antigravity (Variante 2A – `run_workflow`):**
   - Einstiegspunkt: `/run-factory <PROJ-X | #Issue>` (Skill unter [.agents/skills/run-factory/SKILL.md](.agents/skills/run-factory/SKILL.md)).
   - Orchestrator: [workflows/antigravity/factory_workflow.py](workflows/antigravity/factory_workflow.py) mit Schema [workflows/antigravity/workflow.json](workflows/antigravity/workflow.json).
   - Jede Phase läuft als eigener `agent(...)`-Turn im selben `run_workflow`-Lauf. Testszenarien aus der Prüfung werden ausschließlich im Speicher des Orchestrators gehalten und nie ins Repo geschrieben oder an den Bau-Agenten weitergegeben.

2. **Hintergrund-Runner mit `agy` CLI (Variante 2B – `runtime: "local"`):**
   - [runner/main.ts](runner/main.ts) pollt GitHub Issues mit Label `factory` und startet lokale Hintergrundprozesse via [image/entrypoint.sh](image/entrypoint.sh) (`agy -p ... --dangerously-skip-permissions --mode auto --output-format stream-json`).
   - Nutzt die bestehende lokale Antigravity-/Google-Account-Anmeldung (OAuth/Keychain) ohne API-Key.
   - Verbesserungs-Läufe nutzen [image/improve.sh](image/improve.sh) und [playbooks/improve.md](playbooks/improve.md).

## Skills unter `.agents/skills/`

- `init` — Projekt-Initialisierung (PRD, Stack, Design-System, `features/INDEX.md`, `.factory/setup.json`)
- `write-spec` — Feature-Spezifikation im Interview (`features/PROJ-X-.../spec.md`)
- `to-factory` — Erstellt das GitHub Issue mit Label `factory`
- `run-factory` — Startet die native 3-Phasen-Pipeline in Antigravity über `run_workflow`
- `architecture` — Erstellt `design.md` ohne Code-Snippets
- `build` — Implementierung (Backend, UI, Verdrahtung, Tests) nach `spec.md` + `design.md`
- `qa` — Prüfung gegen alle AK/EC, Sicherheitsprüfung, `qa-report.md`

## Verbindliche Regeln für alle Agenten

- **`spec.md` ist der Vertrag** und wird von keinem Factory-Agenten verändert.
- **Nie selbst mergen:** kein `gh pr merge`, kein Push auf den Standard-Branch.
- **Unabhängige Abnahme:** Testszenarien aus der Prüfung sind für Bau-Agenten unsichtbar.
- **Pflicht-Checks:** Vor dem Abschluss eines Baus müssen alle Checks aus `.factory/setup.json` (`factory-verify`) auf dem finalen Commit grün sein.
