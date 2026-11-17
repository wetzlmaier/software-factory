**Variante 1 (1:1 Server-/Docker-Portierung auf die Antigravity CLI `agy`)** wurde umgesetzt.

### Umgesetzte Änderungen

1. **Docker-Image & Container-Entrypoints**
   - [image/Dockerfile](image/Dockerfile#L1-L32): Installiert die offizielle Antigravity CLI (`https://antigravity.google/cli/install.sh`) für `pwuser` statt Claude Code.
   - [image/entrypoint.sh](image/entrypoint.sh):
     - Stellt Workflow-Skills unter `$HOME/.gemini/config/skills/` sowie in `/work/repo/.agents/skills/` bereit (mit `.agents/` in `.git/info/exclude`, damit `factory-verify` ein sauberes Arbeitsverzeichnis sieht).
     - Konfiguriert bei gesetztem `GEMINI_API_KEY` / `GOOGLE_API_KEY` automatisch `$HOME/.gemini/antigravity-cli/settings.json` (`{"modelProvider":"gemini"}`) für den Headless-Containerbetrieb.
     - Kombiniert `/factory/playbook.md` und `/work/prompt.md` zu `/work/full-prompt.md` und startet `agy -p ... --add-dir "/factory/workflows/$WORKFLOW" --dangerously-skip-permissions --mode auto --output-format stream-json` (mit optionalem `--model` sofern `MODEL != "inherit"`), Ausgabe nach `/work/agy.jsonl` bzw. `/work/agy.err`.
   - [image/improve.sh](image/improve.sh): Analog auf `agy -p`, `GEMINI_API_KEY`-/`settings.json`-Konfiguration und `/work/agy.jsonl` umgestellt.

2. **Runner, Setup & Konfiguration**
   - [runner/main.ts](runner/main.ts):
     - `loadConfig()` setzt Standard-`model` auf `"inherit"`.
     - `redact()` maskiert zusätzlich `GEMINI_API_KEY`, `GOOGLE_API_KEY` und `AIza...`-Schlüssel.
     - `dockerAuthArgs()` (verwendet in `launch()` und `maybeImprove()`) reicht gesetzte Auth-Env-Variablen (`GEMINI_API_KEY`, `GOOGLE_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`) an den Container weiter oder mountet alternativ `~/.gemini/antigravity-cli` nach `/home/pwuser/.gemini/antigravity-cli`.
     - `finish()` liest `agy.jsonl` / `agy.err` (mit Fallback auf `claude.jsonl` / `claude.err`), wertet `.result ?? .text ?? .content` aus und meldet Fehler neutral als `Antigravity CLI wurde mit einem Fehler beendet`.
     - `main()` prüft auf einen der API-Keys oder ein vorhandenes `~/.gemini/antigravity-cli`-Verzeichnis.
   - [setup.sh](setup.sh#L82): Prüft `/etc/software-factory/secrets.env` auf `GEMINI_API_KEY` / `GOOGLE_API_KEY` (oder Claude-Fallbacks).
   - [factory.config.example.json](factory.config.example.json#L7): `"model": "inherit"`.

3. **Lokale Skills, Skripte, Doku & Tests**
   - [scripts/install-local-skills.sh](scripts/install-local-skills.sh#L7): Zielpfad auf `$HOME/.gemini/config/skills` umgestellt.
   - [scripts/install-local-skills.ps1](scripts/install-local-skills.ps1): PowerShell-Skript für Windows erstellt (Junction mit Copy-Fallback nach `$HOME\.gemini\config\skills`).
   - [local-skills/init/SKILL.md](local-skills/init/SKILL.md#L57) (`AGENTS.md`, `GEMINI.md` ergänzt), [scripts/new-project.sh](scripts/new-project.sh#L36) und [README.md](README.md) aktualisiert.
   - [runner/main.test.ts](runner/main.test.ts#L56-L65): `redact`-Test um Gemini-/Google-API-Keys erweitert sowie neuen Test für `finish()` mit `agy.jsonl` ergänzt.

---

### Verifikation

- **Bash-Syntax (`C:\Program Files\Git\bin\bash.exe -n`):** Alle 5 geprüften Skripte (`image/entrypoint.sh`, `image/improve.sh`, `setup.sh`, `scripts/install-local-skills.sh`, `scripts/new-project.sh`) mit `BASH_OK` bestanden.
- **PowerShell-Syntax ([scripts/install-local-skills.ps1](scripts/install-local-skills.ps1)):** `PS1_OK` (0 Parser-Fehler).
- **JSON-Validierung ([factory.config.example.json](factory.config.example.json)):** `JSON_OK`.
- **Unit-Tests (`node --test runner/main.test.ts` mit Git-Bash im `PATH`):** **15 von 20 Tests bestanden** (inkl. der erweiterten `redact`-Prüfung und des neuen `agy.jsonl`-Tests). Die **5 fehlgeschlagenen Tests** sind umgebungsbedingt unter Windows:
  - 3× `symlinkSync` (`EPERM: operation not permitted` ohne Developer-Mode/Admin-Rechte),
  - 1× `mkfifo` (`ENOENT` unter Windows),
  - 1× `factory-verify: grün nur, wenn alle Checks bestehen` (Exit-Code `2`, da `jq` in der Git-Bash-Umgebung dieses Windows-Rechners fehlt).
