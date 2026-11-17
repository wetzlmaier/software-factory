"""Native Antigravity Software Factory workflow (Prüfung -> Bau -> Unabhängige Abnahme).

Runs directly inside Antigravity via `run_workflow` using isolated agent turns
for each phase without requiring an external API key or Docker containers.
"""

import json
from pathlib import Path

target = str(args.get("target", "") or "").strip()
if not target:
    raise ValueError("Missing required argument: target (z. B. 'PROJ-1', Spec-Pfad oder '#12')")

repo = str(args.get("repo", "") or "").strip()
raw_max_reworks = args.get("max_reworks", 2)
max_reworks = int(2 if raw_max_reworks is None else raw_max_reworks)
if max_reworks < 0:
    max_reworks = 0

workspace_root = WORKSPACES[0] if WORKSPACES else "."
script_file = globals().get("__file__")
factory_workflows_dir = str(Path(script_file).resolve().parent.parent) if script_file else ""
repo_context = f"GitHub-Repo: {repo}" if repo else "Lokaler Modus (oder aktuelles Git-Repo, falls mit GitHub verknüpft)"

CHECK_SCHEMA = {
    "type": "object",
    "properties": {
        "decision": {"type": "string", "enum": ["approved", "question", "rejected"]},
        "summary": {"type": "string"},
        "question": {"type": "string"},
        "spec_path": {"type": "string"},
        "scenarios_markdown": {"type": "string"},
    },
    "required": ["decision", "summary", "question", "spec_path", "scenarios_markdown"],
}

BUILD_SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string", "enum": ["built", "question", "failed"]},
        "summary": {"type": "string"},
        "question": {"type": "string"},
        "pr_url": {"type": "string"},
        "checks_passed": {"type": "boolean"},
    },
    "required": ["status", "summary", "question", "pr_url", "checks_passed"],
}

ACCEPT_SCHEMA = {
    "type": "object",
    "properties": {
        "decision": {"type": "string", "enum": ["accepted", "rework", "unresolved"]},
        "summary": {"type": "string"},
        "findings_markdown": {"type": "string"},
    },
    "required": ["decision", "summary", "findings_markdown"],
}


def build_check_prompt() -> str:
    return f"""Du bist der **Factory Prüfer** in Phase **Prüfung**.
Arbeite streng nach dem Factory-Playbook (ohne selbst Code zu schreiben, ohne Commits, ohne Push).

Auftrag:
- Ziel: {target}
- Workspace: {workspace_root}
- {repo_context}

Regeln & Vorgehen:
1. Finde die Aufgabe:
   - Handelt es sich um ein Feature (z. B. `PROJ-X` oder Spec-Pfad), suche die `spec.md` unter `features/<ordner>/spec.md` (oder über das GitHub-Issue, falls `#N` angegeben wurde).
   - Handelt es sich um einen Bug (z. B. GitHub-Issue ohne Feature-Spec), prüfe Issue und Kommentare.
2. Feature ohne gültige `spec.md` → `decision: "rejected"` mit Begründung und Hinweis, zuerst `/write-spec` auszuführen.
3. Bei vorhandener `spec.md`: Lies die Spec vollständig sowie `docs/stack.md`, `docs/PRD.md`, `features/INDEX.md` (falls vorhanden) und verschaffe dir einen Überblick über den bestehenden Code.
4. Prüfe:
   - Ist jedes Akzeptanzkriterium eindeutig testbar?
   - Gibt es Widersprüche in der Spec, zu anderen Features, zur PRD oder zum bestehenden Code?
   - Passt alles zum Stack in `docs/stack.md` oder fehlen Voraussetzungen?
5. Entscheidung:
   - Klein und eindeutig klärbar → `decision: "question"` mit 2–3 konkreten Optionen + Empfehlung in `question` (und `scenarios_markdown: ""`). Frage niemals interaktiv über Chat-Tools (`ask_question`).
   - Grundlegend nicht baubar → `decision: "rejected"` mit Grund und notwendigen Anpassungen in `question` (und `scenarios_markdown: ""`).
   - Baubar → `decision: "approved"` und erstelle **Testszenarien für die spätere unabhängige Abnahme** ausschließlich im Rückgabefeld `scenarios_markdown` (pro AK und wichtigstem Randfall mindestens ein Szenario `S-1`..., mit Bezug `AK-x`, Ausgangslage, konkreten Schritten aus Nutzersicht ohne Dateinamen/Code-Details, erwartetem Ergebnis).
6. **WICHTIG:** Schreibe die Testszenarien **NIEMALS** in eine Datei im Repository, in Commits oder in GitHub-Kommentare! Gib sie ausschließlich über `finish` im Feld `scenarios_markdown` zurück."""


def build_dev_prompt(spec_path: str, check_summary: str) -> str:
    stack_hint = (
        f"Stack-Packs liegen ggf. unter `{factory_workflows_dir}/starter-kit/stacks/`."
        if factory_workflows_dir
        else ""
    )
    return f"""Du bist der **Factory Entwickler** in Phase **Bau**.
Arbeite streng nach dem Factory-Playbook und dem Workflow (`architecture` -> `build` -> `qa`).

Auftrag:
- Ziel: {target}
- Spec-Pfad: {spec_path or "(siehe Ziel/Issue)"}
- Workspace: {workspace_root}
- {repo_context}
- Freigabe-Notiz aus der Prüfung: {check_summary}

Feste Regeln:
- Frage niemals im Chat (`ask_question`). Bei echten Blockern/Unklarheiten beende mit `status: "question"` und nenne 2–3 Optionen mit Empfehlung im Feld `question`.
- **Die Spec ist der Vertrag:** Ändere `spec.md` niemals!
- **Nie selbst mergen:** Kein `gh pr merge`, kein Push auf den Standard-Branch (`main`/`master`).
- Arbeite auf einem Feature-Branch (z. B. `factory/{target.lstrip('#')}`), falls ein Git-Repo aktiv ist und du noch auf dem Standard-Branch stehst.
- {stack_hint}

Schritte:
1. **Architektur (`architecture`):** Lies `spec.md`, `docs/stack.md`, `docs/PRD.md`, `docs/design-system.md`, `features/INDEX.md` und schreibe bei Features `design.md` (ohne Code-Snippets!) im Feature-Ordner. Bei Bugs: reproduziere den Fehler und schreibe einen roten Test.
2. **Umsetzung (`build`):** Implementiere das Feature bzw. den Fix sauber nach Stack-Konventionen (`docs/stack.md` + Stack-Packs) in kleinen, sinnvollen Commits.
3. **Tests & QA (`qa`):** Führe alle Pflicht-Checks aus `.factory/setup.json` aus, prüfe alle AK-x und EC-x (bei UI auch im Browser mit Playwright/Dev-Server auf freiem Port und danach sauber stoppen) und erstelle bei Features `qa-report.md` im Feature-Ordner.
4. **Abschluss:** Alle Änderungen committen. Falls Git-Remote + `gh` konfiguriert sind und es dem Workflow entspricht, pushe den Feature-Branch und erstelle einen PR (`pr_url`), sonst lasse `pr_url` leer (`""`). Setze `checks_passed` nur auf `true`, wenn alle Checks aus `.factory/setup.json` (bzw. Tests/Build) nach dem letzten Commit grün sind."""


def build_rework_prompt(spec_path: str, findings_markdown: str, round_nr: int) -> str:
    return f"""Du bist der **Factory Entwickler (Rework)** in Nachbesserungsrunde {round_nr}.
Die unabhängige Abnahme hat Befunde gemeldet. Behebe genau diese Befunde, ohne neue Risiken einzuführen.

Auftrag:
- Ziel: {target}
- Spec-Pfad: {spec_path or "(siehe Ziel/Issue)"}
- Workspace: {workspace_root}
- {repo_context}

Befunde aus der Abnahme:
{findings_markdown}

Regeln:
- Ändere `spec.md` niemals. Nie selbst mergen, nie auf den Standard-Branch pushen.
- Behebe alle gemeldeten Befunde nachvollziehbar, aktualisiere Tests und `qa-report.md` (falls vorhanden).
- Führe danach alle Pflicht-Checks aus `.factory/setup.json` (bzw. Test/Build/Lint) erneut aus und committe deine Änderungen (und pushe auf den Feature-Branch, falls ein Remote/PR existiert).
- Stoppe alle von dir gestarteten Dev-Server vor dem Beenden."""


def build_accept_prompt(spec_path: str, scenarios_markdown: str, round_nr: int, is_last: bool) -> str:
    last_note = (
        "DIES IST DIE LETZTE RUNDE. Keine Rückgabe (`rework`) mehr! "
        "Wenn alle Szenarien bestanden sind → `decision: \"accepted\"`. "
        "Wenn mindestens ein Szenario nicht bestanden oder ein schweres Problem offen ist → `decision: \"unresolved\"`."
        if is_last
        else "Wenn ein Szenario nicht bestanden oder ein schweres Problem gefunden wird → `decision: \"rework\"` mit klaren, nachstellbaren Befunden in `findings_markdown`."
    )
    return f"""Du bist der **Unabhängige Prüfer** in Phase **Abnahme** (Runde {round_nr}).
Du hast nichts entwickelt und vertraust keiner Behauptung aus vorherigen Schritten. Du prüfst nur, was du selbst siehst.
**Kein Produktcode ändern, keine Commits, kein Push!**

Auftrag:
- Ziel: {target}
- Spec-Pfad: {spec_path or "(siehe Ziel/Issue)"}
- Workspace: {workspace_root}
- {repo_context}

Geheime Testszenarien (nur für dich sichtbar):
{scenarios_markdown or "_Keine vorab definierten Szenarien übergeben; leite sie direkt aus den Akzeptanzkriterien der Spec ab._"}

Vorgehen:
1. Lies `spec.md` vollständig.
2. Führe alle Pflicht-Checks aus `.factory/setup.json` (falls vorhanden) selbst aus.
3. Bei Web-/UI-Apps: Starte den Dev-Server (`.factory/setup.json` → `dev`) auf einem freien Port, teste **jedes Szenario** im Browser (z. B. mit Playwright/Chromium), prüfe auf Konsolenfehler, kaputte Darstellung bei 375px und Abstürze. Stoppe deinen Dev-Server anschließend wieder sauber.
4. Dokumentiere das Ergebnis für jedes Szenario (`✅` / `❌` mit kurzer Begründung), gefundene Probleme mit Repro-Schritten und Check-Ergebnissen im Feld `findings_markdown`.
5. Entscheidung:
   - Alle Szenarien bestanden, Checks grün, keine schweren Probleme → `decision: "accepted"`.
   - {last_note}"""


phase("Prüfung")
log(f"Starte Prüfung für {target} ({repo_context})")
check_result = await agent(
    build_check_prompt(),
    schema=CHECK_SCHEMA,
    role="Factory Prüfer",
    workspace="inherit",
)
log(f"Prüfung Ergebnis: {check_result['decision']} - {check_result['summary']}")

if check_result["decision"] != "approved":
    outcome = {
        "phase": "check",
        "decision": check_result["decision"],
        "summary": check_result["summary"],
        "question": check_result["question"],
        "spec_path": check_result["spec_path"],
    }
    print(json.dumps(outcome, ensure_ascii=False, indent=2))
else:
    spec_path = check_result["spec_path"]
    # Wichtig: scenarios_markdown bleibt im Speicher des Orchestrators und wird NIE an Bau-Agenten übergeben.
    secret_scenarios = check_result["scenarios_markdown"]

    phase("Bau")
    log(f"Starte Bau für {target} (Spec: {spec_path or 'n/a'})")
    build_result = await agent(
        build_dev_prompt(spec_path, check_result["summary"]),
        schema=BUILD_SCHEMA,
        role="Factory Entwickler",
        workspace="inherit",
    )
    log(
        f"Bau Ergebnis: {build_result['status']} "
        f"(checks_passed={build_result['checks_passed']}) - {build_result['summary']}"
    )

    if build_result["status"] != "built":
        outcome = {
            "phase": "build",
            "status": build_result["status"],
            "summary": build_result["summary"],
            "question": build_result["question"],
            "pr_url": build_result["pr_url"],
            "checks_passed": build_result["checks_passed"],
        }
        print(json.dumps(outcome, ensure_ascii=False, indent=2))
    else:
        final_accept = None
        pr_url = build_result["pr_url"]

        for round_idx in range(max_reworks + 1):
            round_nr = round_idx + 1
            is_last = round_idx >= max_reworks

            phase("Unabhängige Abnahme" if round_nr == 1 else f"Unabhängige Abnahme (Runde {round_nr})")
            log(f"Starte unabhängige Abnahme Runde {round_nr}/{max_reworks + 1} (last={is_last})")
            accept_result = await agent(
                build_accept_prompt(spec_path, secret_scenarios, round_nr, is_last),
                schema=ACCEPT_SCHEMA,
                role="Unabhängiger Prüfer",
                workspace="inherit",
            )
            log(f"Abnahme Runde {round_nr}: {accept_result['decision']} - {accept_result['summary']}")

            if accept_result["decision"] == "accepted":
                final_accept = accept_result
                break

            if is_last:
                if accept_result["decision"] == "rework":
                    accept_result["decision"] = "unresolved"
                final_accept = accept_result
                break

            phase(f"Nachbesserung (Runde {round_nr})")
            log(f"Starte Nachbesserung Runde {round_nr} aufgrund der Abnahme-Befunde")
            rework_result = await agent(
                build_rework_prompt(spec_path, accept_result["findings_markdown"], round_nr),
                schema=BUILD_SCHEMA,
                role="Factory Entwickler (Rework)",
                workspace="inherit",
            )
            log(
                f"Nachbesserung Runde {round_nr}: {rework_result['status']} "
                f"(checks_passed={rework_result['checks_passed']}) - {rework_result['summary']}"
            )
            if rework_result["pr_url"]:
                pr_url = rework_result["pr_url"]
            if rework_result["status"] != "built":
                final_accept = {
                    "decision": "unresolved",
                    "summary": f"Nachbesserung abgebrochen ({rework_result['status']}): {rework_result['summary']}",
                    "findings_markdown": rework_result["question"] or accept_result["findings_markdown"],
                }
                break

        outcome = {
            "phase": "accept",
            "decision": final_accept["decision"] if final_accept else "unresolved",
            "summary": final_accept["summary"] if final_accept else "",
            "findings_markdown": final_accept["findings_markdown"] if final_accept else "",
            "pr_url": pr_url,
            "spec_path": spec_path,
        }
        print(json.dumps(outcome, ensure_ascii=False, indent=2))
