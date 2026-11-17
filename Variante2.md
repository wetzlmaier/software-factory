**Variante 2 (nativ in Antigravity und lokal ohne API-Key)** wurde vollständig umgesetzt.

### Umgesetzte Änderungen

1. **Skills für Antigravity & Workspace-Integration**
   - Alle 7 Skills (`init`, `write-spec`, `to-factory`, `run-factory`, `architecture`, `build`, `qa`) unter [.agents/skills/](.agents/skills/) bereitgestellt.
   - Neuer Skill [local-skills/run-factory/SKILL.md](local-skills/run-factory/SKILL.md) zum Starten der dreiphasigen Pipeline direkt in Antigravity über `run_workflow`.
   - [local-skills/init/SKILL.md](local-skills/init/SKILL.md#L57) um `AGENTS.md` und `GEMINI.md` ergänzt.
   - Globale Installationsskripte auf `~/.gemini/config/skills` umgestellt bzw. ergänzt: [scripts/install-local-skills.sh](scripts/install-local-skills.sh) (Linux/macOS, inkl. optionaler Verlinkung nach `~/.claude/skills`) und [scripts/install-local-skills.ps1](scripts/install-local-skills.ps1) (Windows PowerShell).

2. **Nativer Antigravity-Workflow (Variante 2A – `run_workflow`)**
   - [workflows/antigravity/workflow.json](workflows/antigravity/workflow.json): Argument-Schema (`target`, `repo`, `max_reworks`).
   - [workflows/antigravity/factory_workflow.py](workflows/antigravity/factory_workflow.py): Führt `phase("Prüfung")`, `phase("Bau")` und `phase("Unabhängige Abnahme")` (mit Rework-Schleife bis `max_reworks`) als getrennte `agent(...)`-Aufrufe aus. `scenarios_markdown` aus der Prüfung bleibt ausschließlich im Speicher des Orchestrators und wird nie an den Bau-Agenten übergeben oder ins Repo geschrieben.

3. **Hintergrund-Runner & Job-Skripte auf `agy` ohne API-Key-Zwang (Variante 2B)**
   - [image/entrypoint.sh](image/entrypoint.sh) und [image/improve.sh](image/improve.sh): Parametrisiert über `FACTORY_WORK`, `FACTORY_ROOT`, `SCENARIOS_DIR` und `FACTORY_DATA`; ruft `agy -p ... --dangerously-skip-permissions --mode auto --output-format stream-json` auf, übernimmt Skills nach `~/.gemini/config/skills/` und `.agents/skills/` (über `.git/info/exclude` ausgeblendet) und löst Container-Pfade im kombinierten Prompt auf.
   - [image/bin/factory-report](image/bin/factory-report#L95-L98) und [image/bin/factory-screenshot](image/bin/factory-screenshot#L16-L45): Nutzen jetzt wie `factory-verify` `${FACTORY_WORK:-/work}` statt fest `/work`.
   - [runner/main.ts](runner/main.ts):
     - `Config` um `runtime?: "local" | "docker"` erweitert (`loadConfig` setzt Standard `runtime: "local"`, `model: "inherit"`).
     - `runtime === "local"` startet lokale `bash`-Prozesse über `Bun.spawn` mit `proc.json`-Tracking, ohne API-Key-Zwang in `main()` und ohne Docker-Abhängigkeit.
     - `finish()` wertet `agy.jsonl` / `agy.err` (mit Fallback auf `claude.jsonl` / `claude.err`) aus.
     - `redact()` maskiert zusätzlich `GEMINI_API_KEY`, `GOOGLE_API_KEY` und `AIza...`-Schlüssel.
   - [factory.config.example.json](factory.config.example.json), [AGENTS.md](AGENTS.md) und [README.md](README.md) aktualisiert bzw. angelegt; neue Testfälle in [runner/main.test.ts](runner/main.test.ts#L56-L65) ergänzt.

---

### Verifikation

- **Python-Syntax (`factory_workflow.py` mit `ast.PyCF_ALLOW_TOP_LEVEL_AWAIT`):** `SYNTAX_OK` (Exit-Code 0).
- **JSON-Validierung (`workflow.json`, `factory.config.example.json`):** `JSON_OK` (Exit-Code 0).
- **Skill-Frontmatter (`.agents/skills/*/SKILL.md`):** Alle 7 Skills (`architecture`, `build`, `init`, `qa`, `run-factory`, `to-factory`, `write-spec`) mit `SKILL_OK` geprüft.
- **Bash-Syntax (`bash -n` über Git-Bash):** Alle 6 Skripte (`image/entrypoint.sh`, `image/improve.sh`, `image/bin/factory-report`, `image/bin/factory-screenshot`, `image/bin/factory-verify`, `scripts/install-local-skills.sh`) mit `BASH_OK` bestanden.
- **PowerShell-Parser (`scripts/install-local-skills.ps1`):** `PS1_OK` (0 Parse-Fehler).
- **Runner-Tests (`node --test runner/main.test.ts` mit Git-Bash im `PATH`):** **15 von 20 Tests bestanden** (inkl. aller State-/Redaction-/`agy.jsonl`-Tests und `factory-verify` bei ungültigem Setup). Die **5 fehlgeschlagenen Tests** sind Windows-Umgebungsbedingt:
  - 3× `symlinkSync` (`EPERM: operation not permitted` unter Windows ohne Developer-Mode/Admin-Rechte),
  - 1× `mkfifo` (`ENOENT` unter Windows),
  - 1× `factory-verify: grün nur, wenn alle Checks bestehen` (Exit-Code `2`, da `jq` in der Git-Bash-Umgebung dieses Windows-Rechners fehlt).
