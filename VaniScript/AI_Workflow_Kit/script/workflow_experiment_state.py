#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

EXPERIMENT_NAME = "context-economy"
EXPERIMENT_BRANCH = "experiment/context-economy-v3.2"
SCHEMA_VERSION = 3

BASE_RESTORE_PATHS = (
    ".omp/AGENTS.md",
    ".omp/agents/workflow-coder.md",
    ".omp/agents/workflow-coder-backup.md",
    ".omp/agents/workflow-reviewer.md",
    ".omp/agents/workflow-reviewer-backup.md",
    ".omp/agents/workflow-tester.md",
    ".omp/agents/workflow-tester-backup.md",
    ".omp/commands/work-update.md",
    ".omp/commands/workflow-update.md",
    ".omp/commands/workflow.md",
    ".omp/lib/workflow-dashboard-extension.ts",
    ".omp/lib/workflow-dashboard-panel.ts",
    "AI_Workflow_Kit/docs/AI/ORCHESTRATOR.md",
)

LEGACY_ONLY_PATHS = (
    ".omp/lib/workflow-context-economy-core.ts",
    ".omp/lib/workflow-context-economy.ts",
    ".omp/lib/workflow-context-snapshot.ts",
    ".omp/tests/workflow-context-economy.selftest.ts",
    "AI_Workflow_Kit/docs/AI/WORKER_OUTPUT_BUDGET.md",
    "AI_Workflow_Kit/script/workflow_experiment.selftest.sh",
    "AI_Workflow_Kit/script/workflow_experiment_config.py",
    "AI_Workflow_Kit/script/workflow_experiment_config.selftest.py",
    "AI_Workflow_Kit/script/workflow_hotkeys.py",
    "AI_Workflow_Kit/script/workflow_hotkeys.selftest.py",
)

OVERLAY_PATHS = (
    ".omp/extensions/workflow-context-economy.ts",
    ".omp/tests/workflow-context-economy-main-only.selftest.ts",
    ".omp/commands/workflow-experiment.md",
    "AI_Workflow_Kit/docs/AI/CONTEXT_ECONOMY.md",
    "AI_Workflow_Kit/script/workflow_experiment.sh",
    "AI_Workflow_Kit/script/workflow_experiment_state.py",
    "EXPERIMENT_CONTEXT_ECONOMY.md",
)
ADDITIVE_PATHS = (*OVERLAY_PATHS, ".omp/workflow-context-policy.json")

OWNED_CONFIG_SECTIONS = ("cycleOrder", "contextPromotion", "compaction")
EXPERIMENT_CONFIG_SECTIONS: dict[str, str] = {
    "cycleOrder": """cycleOrder:
  - workflow_orchestrator
  - workflow_orchestrator_backup
""",
    "contextPromotion": """contextPromotion:
  enabled: false
""",
    "compaction": """compaction:
  enabled: false
  thresholdPercent: -1
  thresholdTokens: -1
  midTurnEnabled: false
  autoContinue: true
  idleEnabled: false
  asyncEnabled: false
  methodOrder:
    - shake
    - soft
  remoteEnabled: false
  supersedeReads: true
  dropUseless: true
""",
}

CYCLE_ACTION = "app.model.cycleForward"
AGENT_HUB_ACTION = "app.agents.hub"
EXPERIMENT_CYCLE_ACTION = """app.model.cycleForward:
  - Ctrl+P
  - Alt+Q
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent), text=True)
    tmp = Path(temporary)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if source.stat().st_mode & stat.S_IXUSR:
        destination.chmod(destination.stat().st_mode | stat.S_IXUSR)


def copy_path(source: Path, destination: Path) -> None:
    if source.is_dir():
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, destination, copy_function=shutil.copy2)
    else:
        copy_file(source, destination)


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def is_additive_marker(marker: Path) -> bool:
    payload = read_json(marker)
    return payload.get("schema_version") in (2, SCHEMA_VERSION) and payload.get("overlay_mode") == "additive"


def is_current_marker(marker: Path) -> bool:
    payload = read_json(marker)
    return payload.get("schema_version") == SCHEMA_VERSION and payload.get("overlay_mode") == "additive"


def looks_legacy(target: Path) -> bool:
    marker = target / ".omp/workflow-context-policy.json"
    if marker.exists() and not is_additive_marker(marker):
        return True
    for relative in (
        ".omp/lib/workflow-context-economy.ts",
        ".omp/lib/workflow-context-economy-core.ts",
        "AI_Workflow_Kit/docs/AI/WORKER_OUTPUT_BUDGET.md",
    ):
        if (target / relative).exists():
            return True
    dashboard = target / ".omp/lib/workflow-dashboard-extension.ts"
    try:
        text = dashboard.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        text = ""
    return "workflow-context-economy" in text or "workflowContextEconomy" in text


def find_baseline_candidate(root: Path, relative: Path) -> Path | None:
    direct = (
        root / relative,
        root / "files" / relative,
        root / "overlay" / relative,
        root / "workflow" / relative,
        root / "baseline" / relative,
    )
    for candidate in direct:
        if candidate.is_file():
            return candidate
    if not root.exists():
        return None
    suffix = relative.as_posix()
    matches: list[Path] = []
    for candidate in root.rglob(relative.name):
        if not candidate.is_file() or not candidate.as_posix().endswith(suffix):
            continue
        try:
            if candidate.stat().st_size > 5_000_000:
                continue
        except OSError:
            continue
        matches.append(candidate)
    if not matches:
        return None
    matches.sort(key=lambda path: (len(path.relative_to(root).parts), str(path)))
    return matches[0]


def find_original_config(old_baseline: Path) -> Path | None:
    candidates: list[Path] = []
    for candidate in (
        old_baseline / ".omp/config.yml",
        old_baseline / "files/.omp/config.yml",
        old_baseline / "overlay/.omp/config.yml",
    ):
        if candidate.is_file():
            candidates.append(candidate)
    if old_baseline.exists():
        for candidate in old_baseline.rglob("config.yml"):
            if not candidate.is_file():
                continue
            try:
                text = candidate.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            if "modelRoles:" in text or candidate.as_posix().endswith(".omp/config.yml"):
                candidates.append(candidate)
    if not candidates:
        return None
    unique = sorted(set(candidates), key=lambda p: (len(p.relative_to(old_baseline).parts), str(p)))
    return unique[0]


# ---- YAML top-level section patching -------------------------------------

_TOP_KEY = re.compile(r"^([A-Za-z0-9_.-]+):(?:\s.*)?$")


def top_key(line: str) -> str | None:
    if not line or line[0].isspace() or line.lstrip().startswith("#"):
        return None
    match = _TOP_KEY.match(line.rstrip("\r\n"))
    return match.group(1) if match else None


def section_ranges(text: str) -> dict[str, tuple[int, int]]:
    lines = text.splitlines(keepends=True)
    starts = [(key, index) for index, line in enumerate(lines) if (key := top_key(line)) is not None]
    result: dict[str, tuple[int, int]] = {}
    for position, (key, start) in enumerate(starts):
        end = starts[position + 1][1] if position + 1 < len(starts) else len(lines)
        result[key] = (start, end)
    return result


def extract_section(text: str, key: str) -> str | None:
    bounds = section_ranges(text).get(key)
    if bounds is None:
        return None
    lines = text.splitlines(keepends=True)
    start, end = bounds
    return "".join(lines[start:end]).rstrip() + "\n"


def replace_sections(text: str, replacements: dict[str, str | None]) -> str:
    lines = text.splitlines(keepends=True)
    ranges = section_ranges(text)
    pending = dict(replacements)
    output: list[str] = []
    index = 0
    while index < len(lines):
        key = top_key(lines[index])
        if key in pending and key in ranges:
            replacement = pending.pop(key)
            if replacement:
                output.append(replacement.rstrip() + "\n")
            index = ranges[key][1]
            continue
        output.append(lines[index])
        index += 1
    for key in OWNED_CONFIG_SECTIONS:
        if key not in pending:
            continue
        replacement = pending.pop(key)
        if not replacement:
            continue
        if output and output[-1].strip():
            output.append("\n")
        output.append(replacement.rstrip() + "\n")
    return "".join(output).rstrip() + "\n"


def capture_config_baseline(config: Path, output: Path, original: Path | None) -> None:
    source_path = original if original and original.is_file() else config
    source = source_path.read_text(encoding="utf-8")
    payload = {
        "schema_version": SCHEMA_VERSION,
        "captured_at": now_iso(),
        "source": str(source_path),
        "sections": {key: extract_section(source, key) for key in OWNED_CONFIG_SECTIONS},
    }
    atomic_write_text(output, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def apply_config(config: Path) -> None:
    source = config.read_text(encoding="utf-8")
    atomic_write_text(config, replace_sections(source, EXPERIMENT_CONFIG_SECTIONS))


def restore_config(config: Path, baseline: Path) -> None:
    payload = read_json(baseline)
    sections = payload.get("sections")
    if not isinstance(sections, dict):
        raise RuntimeError(f"invalid config baseline: {baseline}")
    replacements = {key: sections.get(key) if isinstance(sections.get(key), str) else None for key in OWNED_CONFIG_SECTIONS}
    source = config.read_text(encoding="utf-8")
    atomic_write_text(config, replace_sections(source, replacements))


def validate_config(config: Path) -> list[str]:
    source = config.read_text(encoding="utf-8")
    cycle = extract_section(source, "cycleOrder") or ""
    promotion = extract_section(source, "contextPromotion") or ""
    compaction = extract_section(source, "compaction") or ""
    errors: list[str] = []
    for role in ("workflow_orchestrator", "workflow_orchestrator_backup"):
        if f"- {role}" not in cycle:
            errors.append(f"cycleOrder missing {role}")
    if "enabled: false" not in promotion:
        errors.append("contextPromotion.enabled must be false")
    for required in (
        "enabled: false",
        "thresholdPercent: -1",
        "thresholdTokens: -1",
        "midTurnEnabled: false",
        "autoContinue: true",
        "idleEnabled: false",
        "asyncEnabled: false",
        "remoteEnabled: false",
        "supersedeReads: true",
        "dropUseless: true",
    ):
        if required not in compaction:
            errors.append(f"compaction missing {required}")
    shake = compaction.find("- shake")
    soft = compaction.find("- soft")
    if shake < 0 or soft < 0 or shake > soft:
        errors.append("compaction.methodOrder must be shake then soft")
    return errors


# ---- keybindings patching ------------------------------------------------

_KEY_ACTION = re.compile(r"^([^:#][^:]*):(?:\s.*)?$")


def action_key(line: str) -> str | None:
    if not line or line[0].isspace() or line.lstrip().startswith("#"):
        return None
    match = _KEY_ACTION.match(line.rstrip("\r\n"))
    return match.group(1).strip() if match else None


def action_range(text: str, action: str) -> tuple[int, int] | None:
    lines = text.splitlines(keepends=True)
    start: int | None = None
    for index, line in enumerate(lines):
        if action_key(line) == action:
            start = index
            break
    if start is None:
        return None
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if action_key(lines[index]) is not None:
            end = index
            break
    return start, end


def extract_action(text: str, action: str) -> str | None:
    bounds = action_range(text, action)
    if bounds is None:
        return None
    lines = text.splitlines(keepends=True)
    start, end = bounds
    return "".join(lines[start:end]).rstrip() + "\n"


def replace_action(text: str, action: str, replacement: str | None) -> str:
    lines = text.splitlines(keepends=True)
    bounds = action_range(text, action)
    if bounds is None:
        output = "".join(lines).rstrip()
        if replacement:
            if output:
                output += "\n\n"
            output += replacement.rstrip()
        return output.rstrip() + "\n" if output else ""
    start, end = bounds
    output = lines[:start]
    if replacement:
        output.append(replacement.rstrip() + "\n")
    output.extend(lines[end:])
    return "".join(output).rstrip() + "\n"


def detect_keybindings_path() -> Path:
    explicit = os.environ.get("PI_CODING_AGENT_DIR")
    if explicit:
        return Path(explicit).expanduser().resolve() / "keybindings.yml"
    try:
        completed = subprocess.run(
            ["omp", "config", "path"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if completed.returncode == 0 and completed.stdout.strip():
            raw = completed.stdout.strip().splitlines()[-1].strip()
            candidate = Path(raw).expanduser()
            directory = candidate.parent if candidate.suffix else candidate
            return directory.resolve() / "keybindings.yml"
    except (OSError, subprocess.SubprocessError):
        pass
    return (Path.home() / ".omp/agent/keybindings.yml").resolve()


def render_action_value(value: Any, action: str) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        if value.lstrip().startswith(action + ":"):
            return value.rstrip() + "\n"
        return f"{action}: {value}\n"
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return action + ":\n" + "".join(f"  - {item}\n" for item in value)
    return None


def find_action_in_old_baseline(old_baseline: Path, action: str) -> str | None:
    if not old_baseline.exists():
        return None
    candidates = sorted(
        (path for path in old_baseline.rglob("*") if path.is_file()),
        key=lambda path: (len(path.relative_to(old_baseline).parts), str(path)),
    )
    for candidate in candidates:
        try:
            if candidate.stat().st_size > 1_000_000:
                continue
            text = candidate.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        if candidate.suffix.lower() == ".json":
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                payload = None
            stack = [payload]
            while stack:
                current = stack.pop()
                if isinstance(current, dict):
                    if action in current:
                        rendered = render_action_value(current.get(action), action)
                        if rendered is not None:
                            return rendered
                    if current.get("action") == action or "action" in current and "file_existed" in current:
                        raw = current.get("value") or current.get("original") or current.get("action_value")
                        if raw is None and isinstance(current.get("action"), str) and str(current.get("action")).lstrip().startswith(action + ":"):
                            raw = current.get("action")
                        rendered = render_action_value(raw, action)
                        if rendered is not None:
                            return rendered
                    for alias in ("cycle_action", "agent_hub_action"):
                        raw = current.get(alias)
                        if isinstance(raw, str) and raw.lstrip().startswith(action + ":"):
                            return raw.rstrip() + "\n"
                    for value in current.values():
                        if isinstance(value, (dict, list)):
                            stack.append(value)
                elif isinstance(current, list):
                    stack.extend(current)
        if action in text:
            rendered = extract_action(text, action)
            if rendered is not None:
                return rendered
    return None


def capture_hotkey_baseline(path: Path, output: Path, old_baseline: Path | None, legacy: bool) -> None:
    exists = path.exists()
    source = path.read_text(encoding="utf-8") if exists else ""
    cycle = find_action_in_old_baseline(old_baseline, CYCLE_ACTION) if legacy and old_baseline else None
    hub = find_action_in_old_baseline(old_baseline, AGENT_HUB_ACTION) if legacy and old_baseline else None
    if cycle is None:
        cycle = extract_action(source, CYCLE_ACTION)
        if legacy and cycle and "Alt+Q" in cycle:
            # Recover the conventional pre-experiment action while retaining any
            # other user chords that can be represented line-by-line.
            kept = [line for line in cycle.splitlines() if "Alt+Q" not in line]
            cycle = "\n".join(kept).rstrip() + "\n" if kept else f"{CYCLE_ACTION}: Ctrl+P\n"
            if cycle.rstrip().endswith(":"):
                cycle = f"{CYCLE_ACTION}: Ctrl+P\n"
    if hub is None:
        hub = extract_action(source, AGENT_HUB_ACTION)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "captured_at": now_iso(),
        "path": str(path),
        "file_existed": exists,
        "cycle_action": cycle,
        "agent_hub_action": hub,
    }
    atomic_write_text(output, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def apply_hotkey(path: Path) -> None:
    source = path.read_text(encoding="utf-8") if path.exists() else ""
    atomic_write_text(path, replace_action(source, CYCLE_ACTION, EXPERIMENT_CYCLE_ACTION))


def restore_hotkey(path: Path, baseline: Path) -> None:
    payload = read_json(baseline)
    source = path.read_text(encoding="utf-8") if path.exists() else ""
    cycle = payload.get("cycle_action") if isinstance(payload.get("cycle_action"), str) else None
    restored = replace_action(source, CYCLE_ACTION, cycle)
    if restored.strip():
        atomic_write_text(path, restored)
    elif path.exists() and not payload.get("file_existed", False):
        path.unlink()
    else:
        atomic_write_text(path, restored)


def validate_hotkey(path: Path, baseline: Path | None = None) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"keybindings file missing: {path}"]
    source = path.read_text(encoding="utf-8")
    cycle = extract_action(source, CYCLE_ACTION) or ""
    if "Ctrl+P" not in cycle:
        errors.append("cycleForward missing Ctrl+P")
    if "Alt+Q" not in cycle:
        errors.append("cycleForward missing Alt+Q")
    if baseline and baseline.exists():
        payload = read_json(baseline)
        original_hub = payload.get("agent_hub_action")
        if isinstance(original_hub, str):
            current_hub = extract_action(source, AGENT_HUB_ACTION)
            if current_hub != original_hub:
                errors.append("app.agents.hub changed from the pre-experiment value")
    return errors


# ---- additive baseline ---------------------------------------------------


def capture_additive_baseline(target: Path, baseline: Path, legacy: bool) -> None:
    baseline.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, Any]] = []
    for raw in ADDITIVE_PATHS:
        relative = Path(raw)
        current = target / relative
        existed = current.exists() and not legacy
        if existed:
            copy_path(current, baseline / "files" / relative)
        entries.append({"path": raw, "existed": existed})
    atomic_write_text(
        baseline / "manifest.json",
        json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "captured_at": now_iso(),
                "legacy_upgrade": legacy,
                "files": entries,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
    )


def ensure_additive_baseline_entries(target: Path, baseline: Path, legacy: bool) -> None:
    manifest = baseline / "manifest.json"
    payload = read_json(manifest)
    entries = payload.get("files")
    if not isinstance(entries, list):
        raise RuntimeError(f"invalid additive baseline: {baseline}")
    known = {entry.get("path") for entry in entries if isinstance(entry, dict)}
    changed = False
    for raw in ADDITIVE_PATHS:
        if raw in known:
            continue
        relative = Path(raw)
        current = target / relative
        existed = current.exists() and not legacy
        if existed:
            copy_path(current, baseline / "files" / relative)
        entries.append({"path": raw, "existed": existed})
        changed = True
    if changed or payload.get("schema_version") != SCHEMA_VERSION:
        payload["schema_version"] = SCHEMA_VERSION
        payload["updated_at"] = now_iso()
        payload["files"] = entries
        atomic_write_text(manifest, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def restore_additive_baseline(target: Path, baseline: Path) -> None:
    payload = read_json(baseline / "manifest.json")
    entries = payload.get("files")
    if not isinstance(entries, list):
        raise RuntimeError(f"invalid additive baseline: {baseline}")
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            continue
        relative = Path(entry["path"])
        destination = target / relative
        if entry.get("existed"):
            source = baseline / "files" / relative
            if not source.exists():
                raise RuntimeError(f"baseline file missing: {source}")
            copy_path(source, destination)
        else:
            remove_path(destination)


# ---- install/rollback/doctor --------------------------------------------


def common_git_dir(target: Path) -> Path:
    completed = subprocess.run(
        ["git", "-C", str(target), "rev-parse", "--git-common-dir"],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise RuntimeError(f"target is not a Git worktree: {target}")
    raw = Path(completed.stdout.strip())
    return raw if raw.is_absolute() else (target / raw).resolve()


def experiment_roots(target: Path) -> tuple[Path, Path, Path]:
    git_dir = common_git_dir(target)
    root = git_dir / "pavans-workflow/experiments/context-economy"
    # Keep the established v2 state directory so upgrades retain the immutable
    # pre-experiment rollback baseline instead of snapshotting an experimental
    # installation as the new baseline.
    return root, root / "v2", root / "baseline"


def forensic_copy(target: Path, paths: tuple[str, ...], destination: Path) -> None:
    for raw in paths:
        source = target / raw
        if not source.exists():
            continue
        copy_path(source, destination / raw)


def restore_base_workflow(target: Path, source_root: Path, old_baseline: Path, state_root: Path) -> list[dict[str, Any]]:
    forensic = state_root / "forensic" / f"pre-v2-{stamp()}"
    forensic_copy(target, BASE_RESTORE_PATHS + LEGACY_ONLY_PATHS, forensic)
    report: list[dict[str, Any]] = []
    for raw in BASE_RESTORE_PATHS:
        relative = Path(raw)
        destination = target / relative
        baseline_candidate = find_baseline_candidate(old_baseline, relative)
        fallback = source_root / relative
        selected = baseline_candidate if baseline_candidate else (fallback if fallback.is_file() else None)
        if selected is None:
            report.append({"path": raw, "restored": False, "reason": "baseline and branch fallback missing"})
            continue
        copy_file(selected, destination)
        report.append({"path": raw, "restored": True, "source": str(selected), "sha256": sha256_file(destination)})
    for raw in LEGACY_ONLY_PATHS:
        remove_path(target / raw)
    atomic_write_text(
        state_root / "v2-migration.json",
        json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "migrated_at": now_iso(),
                "forensic_backup": str(forensic),
                "files": report,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
    )
    return report


def overlay_source(source_root: Path) -> Path:
    return source_root / "AI_Workflow_Kit/experiments/context-economy/v3/overlay"


def copy_overlay(source_root: Path, target: Path) -> None:
    overlay = overlay_source(source_root)
    if not overlay.is_dir():
        raise RuntimeError(f"v3 overlay missing: {overlay}")
    for raw in OVERLAY_PATHS:
        relative = Path(raw)
        source = overlay / relative
        if not source.exists():
            raise RuntimeError(f"overlay file missing: {source}")
        copy_path(source, target / relative)


def write_marker(target: Path, source_commit: str) -> None:
    payload = {
        "schema_version": SCHEMA_VERSION,
        "name": EXPERIMENT_NAME,
        "overlay_mode": "additive",
        "branch": EXPERIMENT_BRANCH,
        "source_commit": source_commit,
        "installed_at": now_iso(),
        "arm_percent": 23,
        "hard_percent": 28,
        "reset_percent": 18,
        "method_order": ["shake", "soft"],
        "scope": "top-level-interactive-main-only",
        "worker_auto_compaction": False,
        "omp_auto_compaction": False,
        "base_dashboard_owned_by_experiment": False,
        "alt_a_owned_by_experiment": False,
    }
    atomic_write_text(target / ".omp/workflow-context-policy.json", json.dumps(payload, indent=2) + "\n")


def source_commit(source_root: Path) -> str:
    completed = subprocess.run(
        ["git", "-C", str(source_root), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip() if completed.returncode == 0 else "unknown"


def install(target: Path, source_root: Path) -> dict[str, Any]:
    target = target.resolve()
    source_root = source_root.resolve()
    base_source_root = Path(os.environ.get("WF_CONTEXT_ECONOMY_BASE_ROOT", str(source_root))).resolve()
    config = target / ".omp/config.yml"
    if not config.is_file():
        raise RuntimeError(f"existing workflow config missing: {config}")
    root, v2_root, old_baseline = experiment_roots(target)
    v2_root.mkdir(parents=True, exist_ok=True)
    legacy = looks_legacy(target) and not is_additive_marker(target / ".omp/workflow-context-policy.json")

    additive_baseline = v2_root / "baseline"
    config_baseline = v2_root / "config-sections.json"
    hotkey_baseline = v2_root / "hotkey-action.json"
    keybindings = detect_keybindings_path()

    if not (additive_baseline / "manifest.json").exists():
        capture_additive_baseline(target, additive_baseline, legacy)
    ensure_additive_baseline_entries(target, additive_baseline, legacy)
    if not config_baseline.exists():
        original_config = find_original_config(old_baseline) if legacy else None
        capture_config_baseline(config, config_baseline, original_config)
    if not hotkey_baseline.exists():
        capture_hotkey_baseline(keybindings, hotkey_baseline, old_baseline, legacy)

    migration: list[dict[str, Any]] = []
    if legacy:
        migration = restore_base_workflow(target, base_source_root, old_baseline, root)

    copy_overlay(source_root, target)
    apply_config(config)
    apply_hotkey(keybindings)
    write_marker(target, source_commit(base_source_root))

    errors = validate(target)
    if errors:
        raise RuntimeError("; ".join(errors))
    return {
        "legacy_repaired": legacy,
        "migration": migration,
        "state_root": str(root),
        "keybindings": str(keybindings),
    }


def rollback(target: Path) -> dict[str, Any]:
    target = target.resolve()
    root, v2_root, _old_baseline = experiment_roots(target)
    additive_baseline = v2_root / "baseline"
    config_baseline = v2_root / "config-sections.json"
    hotkey_baseline = v2_root / "hotkey-action.json"
    if not (additive_baseline / "manifest.json").exists():
        raise RuntimeError(f"additive baseline missing: {additive_baseline}")
    if not config_baseline.exists():
        raise RuntimeError(f"config baseline missing: {config_baseline}")
    if not hotkey_baseline.exists():
        raise RuntimeError(f"hotkey baseline missing: {hotkey_baseline}")

    forensic = root / "forensic" / f"rollback-v2-{stamp()}"
    forensic_copy(target, ADDITIVE_PATHS, forensic)
    restore_config(target / ".omp/config.yml", config_baseline)
    hotkey_payload = read_json(hotkey_baseline)
    raw_path = hotkey_payload.get("path")
    keybindings = Path(raw_path).expanduser() if isinstance(raw_path, str) else detect_keybindings_path()
    restore_hotkey(keybindings, hotkey_baseline)
    restore_additive_baseline(target, additive_baseline)
    return {"forensic_backup": str(forensic), "keybindings": str(keybindings)}


def validate(target: Path) -> list[str]:
    target = target.resolve()
    errors: list[str] = []
    marker = target / ".omp/workflow-context-policy.json"
    if not is_current_marker(marker):
        errors.append("v3 Main-only additive marker missing or invalid")

    for raw in ADDITIVE_PATHS:
        if not (target / raw).exists():
            errors.append(f"additive file missing: {raw}")

    required_base = {
        ".omp/extensions/workflow-dashboard.ts": ("workflowDashboard",),
        ".omp/lib/workflow-dashboard-extension.ts": (
            "task:subagent:progress",
            "task:subagent:lifecycle",
            "registerShortcut",
            'Key.alt("w")',
        ),
        ".omp/lib/workflow-dashboard-panel.ts": (
            "ScrollView",
            "fullscreen: true",
            "mouseTracking: true",
            "readRuntimeTodo",
            "linkRuntimeTodo",
        ),
        ".omp/lib/workflow-dashboard-core.ts": ("DashboardData", "StepCard"),
    }
    for raw, needles in required_base.items():
        path = target / raw
        if not path.is_file():
            errors.append(f"base dashboard file missing: {raw}")
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read {raw}: {error}")
            continue
        for needle in needles:
            if needle not in text:
                errors.append(f"base dashboard capability missing in {raw}: {needle}")
        if "workflow-context-economy" in text or "workflowContextEconomy" in text:
            errors.append(f"experiment leaked into base dashboard file: {raw}")

    extension = target / ".omp/extensions/workflow-context-economy.ts"
    try:
        extension_text = extension.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        extension_text = ""
    for forbidden in ('Key.alt("w")', "Key.alt('w')", 'Key.alt("a")', "Key.alt('a')", AGENT_HUB_ACTION):
        if forbidden in extension_text:
            errors.append(f"experiment extension shadows base/native shortcut: {forbidden}")
    for required in (
        "classifySessionScope",
        "top-level-interactive-main-only",
        "disabled in worker/subagent sessions",
        "worker_auto_compaction: false",
        "ctx.compact",
    ):
        if required not in extension_text:
            errors.append(f"Main-only extension capability missing: {required}")

    config = target / ".omp/config.yml"
    if config.is_file():
        errors.extend(validate_config(config))
    else:
        errors.append(".omp/config.yml missing")

    root, v2_root, _ = experiment_roots(target)
    hotkey_baseline = v2_root / "hotkey-action.json"
    keybindings = detect_keybindings_path()
    errors.extend(validate_hotkey(keybindings, hotkey_baseline))
    return errors


def status(target: Path) -> dict[str, Any]:
    target = target.resolve()
    root, v2_root, _ = experiment_roots(target)
    marker = read_json(target / ".omp/workflow-context-policy.json")
    return {
        "installed": is_additive_marker(target / ".omp/workflow-context-policy.json"),
        "branch": marker.get("branch", EXPERIMENT_BRANCH),
        "source_commit": marker.get("source_commit"),
        "policy": {
            "scope": marker.get("scope"),
            "arm_percent": marker.get("arm_percent"),
            "hard_percent": marker.get("hard_percent"),
            "reset_percent": marker.get("reset_percent"),
            "method_order": marker.get("method_order"),
            "worker_auto_compaction": marker.get("worker_auto_compaction"),
            "omp_auto_compaction": marker.get("omp_auto_compaction"),
        },
        "state_root": str(root),
        "baseline": str(v2_root / "baseline"),
        "legacy_migration": (root / "v2-migration.json").exists(),
        "dashboard_owner": "base-workflow",
        "agent_hub_owner": "OMP-native",
    }


def selftest() -> None:
    sample = """modelRoleStorage: project
modelRoles:
  workflow_orchestrator: custom/main
scalar: keep
cycleOrder:
  - old
contextPromotion:
  enabled: true
compaction:
  thresholdPercent: 85
retry:
  enabled: true
"""
    patched = replace_sections(sample, EXPERIMENT_CONFIG_SECTIONS)
    assert "custom/main" in patched
    assert "scalar: keep" in patched
    assert "retry:\n  enabled: true" in patched
    assert "thresholdPercent: -1" in patched
    assert "enabled: false" in extract_section(patched, "compaction")
    original = {key: extract_section(sample, key) for key in OWNED_CONFIG_SECTIONS}
    restored = replace_sections(patched.replace("custom/main", "custom/new-main"), original)
    assert "custom/new-main" in restored
    assert "thresholdPercent: 85" in restored
    assert "- old" in restored

    hotkeys = """app.message.followUp: Ctrl+Q
app.model.cycleForward: Ctrl+P
app.agents.hub: Alt+A
"""
    patched_hotkeys = replace_action(hotkeys, CYCLE_ACTION, EXPERIMENT_CYCLE_ACTION)
    assert "Alt+Q" in patched_hotkeys
    assert "app.agents.hub: Alt+A" in patched_hotkeys
    restored_hotkeys = replace_action(patched_hotkeys + "theme.toggle: Alt+T\n", CYCLE_ACTION, extract_action(hotkeys, CYCLE_ACTION))
    assert "app.model.cycleForward: Ctrl+P" in restored_hotkeys
    assert "app.agents.hub: Alt+A" in restored_hotkeys
    assert "theme.toggle: Alt+T" in restored_hotkeys
    print("workflow_experiment_state selftest: PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description="Install and manage Pavan's additive context-economy experiment.")
    sub = parser.add_subparsers(dest="command", required=True)

    install_parser = sub.add_parser("install")
    install_parser.add_argument("target", type=Path)
    install_parser.add_argument("source_root", type=Path)

    rollback_parser = sub.add_parser("rollback")
    rollback_parser.add_argument("target", type=Path)

    doctor_parser = sub.add_parser("doctor")
    doctor_parser.add_argument("target", type=Path)

    status_parser = sub.add_parser("status")
    status_parser.add_argument("target", type=Path)

    sub.add_parser("selftest")

    args = parser.parse_args()
    try:
        if args.command == "install":
            print(json.dumps(install(args.target, args.source_root), indent=2, ensure_ascii=False))
        elif args.command == "rollback":
            print(json.dumps(rollback(args.target), indent=2, ensure_ascii=False))
        elif args.command == "doctor":
            errors = validate(args.target)
            if errors:
                for error in errors:
                    print(f"FAIL {error}")
                return 1
            print("Context-economy doctor: ready")
            print("Compaction scope: top-level interactive Main only.")
            print("OMP automatic compaction is disabled globally so workers retain full assignment context.")
            print("Alt+W is owned by the restored base workflow dashboard.")
            print("Alt+A is owned by OMP's native Agent Hub.")
            print("Alt+Q toggles the two Orchestrator roles.")
        elif args.command == "status":
            print(json.dumps(status(args.target), indent=2, ensure_ascii=False))
        else:
            selftest()
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        print(f"ERROR: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
