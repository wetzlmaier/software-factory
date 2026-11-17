# Software Factory

Eine automatisierte Software Factory für **Antigravity (`agy`)** und Claude Code – direkt in deiner Antigravity-Sitzung oder rund um die Uhr über einen Hintergrund-Runner, **komplett ohne API-Key** über deine bestehende Antigravity-Anmeldung.

> 🖥️ **Server (optional für 24/7-Betrieb):** Die Factory läuft lokal auf deinem Rechner oder auf einem Linux-VPS (z. B. Ubuntu 24.04).
> Einrichtung Schritt für Schritt (VPS): **[docs/hostinger-vps-setup.md](docs/hostinger-vps-setup.md)**

**Du entscheidest, was gebaut wird. Die Factory baut es.**

1. Du schreibst lokal mit `/write-spec` die Spec, prüfst sie und pushst sie.
2. **Variante 2A (direkt in Antigravity, ohne Server):** Du startest `/run-factory PROJ-X`. Der native Antigravity-Workflow (`workflows/antigravity/factory_workflow.py`) führt Prüfung, Bau und unabhängige Abnahme nacheinander mit strikt getrennten Agenten aus.
3. **Variante 2B (GitHub-Issue-Runner, ohne API-Key):** Du übergibst die Spec mit `/to-factory` als GitHub Issue (`factory`). Der Runner (`runner/main.ts`) startet im Modus `runtime: "local"` für jede Phase einen eigenen `agy -p`-Lauf mit deiner lokalen Antigravity-Anmeldung (oder optional mit Docker).
4. Du prüfst das Ergebnis bzw. den Pull Request und mergst. **Gemergt wird immer von dir.**

Bugs gehen auch ohne Spec: Issue mit Label `factory` anlegen und beschreiben, was falsch ist und was du erwartest.

**Status auf dem Board:** Neu → In Prüfung → Rückfrage / Abgelehnt → Freigegeben → In Arbeit (Architektur · Umsetzung · Tests) → Abnahme → Review → Fertig, bei technischen Fehlern Fehlgeschlagen. Prüfung, Entwicklung und Abnahme sind getrennte Läufe mit eigenen Agenten-Kontexten.

## Antigravity-Nutzung (ohne API-Key)

### Variante 2A: Direkt in Antigravity (`/run-factory`)

1. **Skills installieren (einmalig global):**
   - Linux / macOS: `./scripts/install-local-skills.sh`
   - Windows (PowerShell): `.\scripts\install-local-skills.ps1`
   Im Factory-Repo selbst liegen alle 7 Skills zusätzlich bereits unter `.agents/skills/`.
2. **Im Projekt:** Briefing in `docs/briefing.md` → `/init` → pro Feature `/write-spec PROJ-X` → `/run-factory PROJ-X`.
3. **Ablauf:** `run_workflow` führt [workflows/antigravity/factory_workflow.py](workflows/antigravity/factory_workflow.py) aus:
   - **Prüfung:** Prüft die Spec und erzeugt Testszenarien ausschließlich im Speicher des Workflows.
   - **Bau:** Ein neuer Entwickler-Agent durchläuft `architecture → build → qa` (ohne die Testszenarien zu kennen).
   - **Unabhängige Abnahme:** Ein unabhängiger Prüfer-Agent testet gegen Spec und Testszenarien (inkl. automatischer Nachbesserungs-Runden bis `max_reworks`).

### Variante 2B: Hintergrund-Runner (`runtime: "local"` mit `agy`)

- Standard in `factory.config.example.json` ist `"runtime": "local"` und `"model": "inherit"`.
- Voraussetzung ist lediglich eine einmalige Anmeldung mit `agy` (Google-Account / Keychain) und `gh auth login` – **kein API-Key nötig**.
- Der Runner startet [image/entrypoint.sh](image/entrypoint.sh) als lokalen Prozess (`agy -p ... --dangerously-skip-permissions --mode auto --output-format stream-json`), trennt Testszenarien über `SCENARIOS_DIR` vom Bau-Lauf und hält Status-Labels sowie GitHub Projects Board aktuell.
- Optional lässt sich in der Konfiguration `"runtime": "docker"` aktivieren (z. B. mit `GEMINI_API_KEY` oder Claude-Token im Container).

## So funktioniert es

```
GitHub Issue (Label "factory")
        │
        ▼
Runner auf deinem Server ── prüft jede Minute die Issues
        │
        ▼
Prozess (`runtime: "local"`, Standard) oder Docker-Container (`runtime: "docker"`) pro Issue
  └─ Antigravity (`agy`) + Playbook + Workflow-Skills
       Triage → Analyse → Umsetzung → Prüfung → Pull Request
        │
        ├─ unklar?  → Frage als Kommentar im Issue, wartet auf dich
        └─ fertig?  → Pull Request mit Checks + Screenshots
                          │
                          ▼
                    Du reviewst und mergst
```

- **Runner** (`runner/`): kleiner Dienst auf deinem Rechner oder Server. Holt Issues, startet lokale `agy`-Läufe (oder Container), setzt Labels und Board-Status. Schreibt selbst keinen Code.
- **Job-Skripte & Image** (`image/`): Entrypoint (`entrypoint.sh`), Verbesserungs-Lauf (`improve.sh`), GitHub CLI, git, Node, Chromium (für Tests und Screenshots) und Factory-Werkzeuge (`factory-report`, `factory-verify`, `factory-screenshot`).
- **Antigravity-Workflow** (`workflows/antigravity/`): Nativer `run_workflow`-Orchestrator (`factory_workflow.py`) für die direkte Ausführung in Antigravity ohne GitHub-Runner-Daemon.
- **Playbook** (`playbooks/factory.md`): die festen Regeln für jeden Lauf. Stages melden, bei Unklarheit fragen statt raten, Pflicht-Checks, nie selbst mergen.
- **Workflow** (`workflows/starter-kit/`): wie entwickelt wird. Standard ist der Workflow aus dem [AI Coding Starter Kit](https://github.com/AlexPEClub/ai-coding-starter-kit): `architecture → build → qa` auf Basis deiner Spec, mit getrennten Dateien pro Feature (`spec.md`, `design.md`, `qa-report.md`). Austauschbar, siehe [workflow.md](workflows/starter-kit/workflow.md).
- **Stack-Packs** (`workflows/starter-kit/stacks/`): Regeln für einen bestimmten Stack (z. B. `nextjs`, `supabase`). Welche gelten, steht in `docs/stack.md` des Projekts. Die Factory ist stack-unabhängig.
- **Lokale Skills** (`local-skills/`): `init` (Projekt aufsetzen inkl. Stack), `write-spec` (Spec im Interview erarbeiten), `to-factory` (an die Factory übergeben), `run-factory` (direkte Pipeline in Antigravity starten). Einmal pro Rechner installieren: `./scripts/install-local-skills.sh` bzw. `.\scripts\install-local-skills.ps1`.
- **Projekt-Vorlage**: [factory-template](https://github.com/AlexPEClub/factory-template), stack-unabhängig. Neues Projekt: `./scripts/new-project.sh mein-projekt`.

## Voraussetzungen

- **Für Variante 2A (direkt in Antigravity):** Google Antigravity (`agy` / App / IDE) – kein API-Key nötig
- **Für Variante 2B (Hintergrund-Runner):** Antigravity CLI (`agy`, einmalig per Google-Account eingeloggt), Bun, GitHub CLI (`gh`) und bash (Linux/macOS oder Git-Bash auf Windows)
- **Optional (Docker-Modus `runtime: "docker"`):** Linux-Server mit Ubuntu 24.04 (mind. 2 vCPU, 8 GB RAM) + `GEMINI_API_KEY` oder Claude-Token

## Schnellstart (Hintergrund-Runner)

```bash
git clone https://github.com/AlexPEClub/software-factory.git /opt/software-factory
cd /opt/software-factory
./setup.sh
```

Danach:
1. **Antigravity-Login (`runtime: "local"`, ohne API-Key):** einmalig `agy` ausführen und im Browser mit deinem Google-Account anmelden (im Docker-Modus stattdessen API-Key/Token in `/etc/software-factory/secrets.env` eintragen)
2. **GitHub-Login:** `gh auth login -s project`
3. **Factory starten:** `systemctl restart software-factory` (oder lokal `bun run runner/main.ts`)
4. **Auf deinem Rechner:** `./scripts/install-local-skills.sh` (bzw. `.\scripts\install-local-skills.ps1`), dann `FACTORY_SERVER=root@DEINE-IP ./scripts/new-project.sh mein-projekt`. Ein bestehendes Repo bindest du mit `./scripts/add-repo.sh dein-name/dein-repo` an.
5. Im Projekt: Briefing in `docs/briefing.md` → `/init` → pro Feature `/write-spec` → `/run-factory` (lokal) oder `/to-factory` (Runner)

Die ausführliche Schritt-für-Schritt-Anleitung (inkl. Server bei Hostinger): [docs/hostinger-vps-setup.md](docs/hostinger-vps-setup.md).

## Messen und verbessern

Jeder Lauf wird mit Dauer, Schritten und Ergebnis in `/var/lib/software-factory/metrics.jsonl` festgehalten. Auswertung auf dem Server:

```bash
factory-stats            # alles
factory-stats --tage 7   # letzte Woche
```

Weil jede Aufgabe denselben Ablauf durchläuft, siehst du so, ob eine Änderung am Playbook, an den Skills oder am Modell etwas bringt: Laufzeit pro Aufgabe, Anteil Rückfragen, wie oft die Abnahme beim ersten Mal besteht.

## Das Ziel-Repo

Die Factory liest `.factory/setup.json` im Ziel-Repo:

```json
{
  "install": "npm ci",
  "dev": "npm run dev -- -p $PORT",
  "checks": {
    "lint": "npm run lint",
    "typecheck": "npx tsc --noEmit",
    "test": "npm test",
    "build": "npm run build"
  }
}
```

`/init` legt sie passend zum Stack an. Braucht dein Stack eine andere Laufzeit als Node oder Python, ergänzt `/init` eine `.factory/Dockerfile`, die auf dem Factory-Image aufbaut.

## Claude-Abo: was ist erlaubt?

Die Factory startet die **unveränderte, offizielle Claude Code CLI** auf deinem eigenen Server. Angemeldet wird mit deinem eigenen Abo über `claude setup-token`, den Weg, den Anthropic für Skripte und CI dokumentiert ([Authentication](https://code.claude.com/docs/en/authentication)). Das Repo speichert oder teilt keine fremden Logins.

- Abo-Limits gelten für die Factory und deine normale Claude-Nutzung zusammen. Starte mit `maxParallel: 1–2`.
- Für Teams oder wenn du die Factory als Dienst für andere betreibst: `ANTHROPIC_API_KEY` verwenden ([Legal and Compliance](https://code.claude.com/docs/en/legal-and-compliance)).
- Stand: November 2026. Anthropic kann die Regeln ändern, prüf die verlinkte Doku.

## Sicherheit und Grenzen (Version 0.1)

- Jeder Lauf hat einen eigenen Container mit Speicher- und Prozesslimit. Standard: zwei Agent-Läufe gleichzeitig (`maxParallel: 2`), passend zu 8 GB RAM.
- Antworten und Änderungswünsche nimmt die Factory nur von dir an (plus `allowedUsers`). Fremde Kommentare sieht der Agent nicht.
- Ein Bau zählt nur, wenn `factory-verify` auf genau dem gepushten Commit grün ist und die Spec unverändert bleibt. Besteht die Abnahme nach zwei Runden nicht, landet der PR mit „Abnahme nicht bestanden“ bei dir, nie als bestanden.
- Vorschauen laufen ohne Zugangsdaten, mit Passwort und mit Domain über HTTPS.
- Die Agents arbeiten mit deinem GitHub-Login. Für mehr Trennung: eigener GitHub-Account für die Factory oder ein Fine-grained Token, der nur deine Factory-Repos erreicht.
- Getestet: Ubuntu 24.04 auf Hostinger KVM 2, Next.js-Projekte. Weitere Stacks sind vorgesehen, aber noch nicht erprobt.

Tests für den Runner: `node --test runner/main.test.ts` (Node 22.6+, ohne GitHub und Docker).

## Lizenz

MIT
