---
name: run-factory
description: >-
  Run the automated Software Factory pipeline (Prüfung -> Bau -> Unabhängige Abnahme)
  natively in Antigravity using run_workflow without an API key, either for a local
  feature (PROJ-X) or a GitHub issue (#N).
argument-hint: "PROJ-X or #issue-number"
user-invocable: true
---

# Software Factory (Native Antigravity Runner)

Führt die komplette dreiphasige Software Factory direkt in deiner bestehenden Antigravity-Sitzung (ohne externen API-Key und ohne Docker-Container) über das `run_workflow`-Tool aus:

1. **Prüfung (`check`)**: Prüft die Spec bzw. Bug-Beschreibung auf Baubarkeit und erstellt Testszenarien (nur im Speicher des Workflows – für den Entwickler-Agenten unsichtbar).
2. **Bau (`build`)**: Ein frischer Entwickler-Agent erstellt Architektur (`design.md`), Implementierung (`build`) sowie Tests/QA (`qa-report.md`) und prüft alle Checks aus `.factory/setup.json`.
3. **Unabhängige Abnahme (`accept`)**: Ein neuer, unabhängiger Prüfer-Agent testet die Umsetzung gegen `spec.md` und die geheimen Testszenarien. Bei Befunden startet automatisch eine Nachbesserungsrunde (bis zu `max_reworks` Runden).

## Voraussetzungen

- Im Ziel-Repo existiert die Spec unter `features/<PROJ-X>-*/spec.md` (oder ein GitHub Issue `#N`).
- Das Workflow-Skript liegt unter `workflows/antigravity/factory_workflow.py` (im Factory-Repo bzw. unter dem konfigurierten Pfad).

## Ausführung

1. Bestimme `target` aus den Argumenten des Nutzers:
   - Feature-ID (z. B. `PROJ-1`), direkter Spec-Pfad (`features/PROJ-1-.../spec.md`) oder Issue-Nummer (`#12`).
   - Fehlt das Argument, prüfe `features/INDEX.md` auf Features mit Status `Planned` oder offene Issues und frage den Nutzer nach dem gewünschten Ziel.
2. Optional: Falls mit GitHub Issues/PRs gearbeitet werden soll, ermittle `repo` (`gh repo view --json nameWithOwner --jq .nameWithOwner`, falls `gh` konfiguriert ist) oder übernimm die Angabe des Nutzers.
3. Starte die Pipeline über `run_workflow`:
   - `ScriptPath`: `<absoluter-pfad-zum-factory-repo>/workflows/antigravity/factory_workflow.py`
     (falls du dich direkt im Factory-Repo befindest, liegt es unter `<workspace>/workflows/antigravity/factory_workflow.py`; prüfe vorab per Dateisuche, wo `factory_workflow.py` liegt).
   - `Description`: `"Software Factory: <target>"`
   - `Args`:
     ```json
     {
       "target": "<target>",
       "repo": "<owner/repo oder weglassen>",
       "max_reworks": 2
     }
     ```
4. Beende den Turn, während der Hintergrund-Workflow läuft, oder werte das Ergebnis aus, sobald `run_workflow` fertig ist:
   - Bei **Rückfrage (`question`)** oder **Ablehnung (`rejected`)** aus der Prüfung: präsentiere die Rückfrage inkl. Optionen bzw. den Ablehnungsgrund direkt dem Nutzer.
   - Bei **Erfolg (`accepted`)**: fasse das Ergebnis, durchgeführte Checks und ggf. den PR-Link bzw. Branch zusammen. **Nie selbst mergen.**
   - Bei **`unresolved` / `failed`**: präsentiere alle offenen Befunde aus dem Abnahmebericht zur Entscheidung durch den Nutzer.
