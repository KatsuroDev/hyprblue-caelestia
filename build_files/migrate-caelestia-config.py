#!/usr/bin/env python3
"""Safely migrate a legacy Caelestia/Hyprland config to the Lua layout.

The migration is intentionally conservative:
- preview-only unless --apply is passed;
- backs up ~/.config/hypr and ~/.config/caelestia before changing anything;
- replaces only the managed ~/.config/hypr tree with the image's current dots;
- moves user overrides into the new ~/.config/caelestia/*.lua files;
- rewrites the old Caelestia shell font schema without touching transparency;
- records anything it cannot translate in a migration report.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

SOURCE_HYPR = Path(os.environ.get("HYPRBLUE_CAELESTIA_SOURCE", "/usr/share/caelestia-dots/hypr"))

# Defaults from the last Hyprlang-based Caelestia layout used by this image.
# Values are compared as text so only real local edits become permanent overrides.
LEGACY_DEFAULTS_TEXT = r"""
terminal=foot
browser=zen-browser
editor=codium
fileExplorer=thunar
touchpadDisableTyping=true
touchpadScrollFactor=0.3
workspaceSwipeFingers=4
gestureFingers=3
gestureFingersMore=4
blurEnabled=true
blurSpecialWs=false
blurPopups=true
blurInputMethods=true
blurSize=8
blurPasses=2
blurXray=false
shadowEnabled=true
shadowRange=20
shadowRenderPower=3
shadowColour=rgba($surfaced4)
workspaceGaps=20
windowGapsIn=5
windowGapsOut=10
singleWindowGapsOut=20
windowOpacity=0.95
windowRounding=15
windowBorderSize=1
activeWindowBorderColour=rgba($primarye6)
inactiveWindowBorderColour=rgba($onSurfaceVariant11)
volumeStep=10
cursorTheme=sweet-cursors
cursorSize=24
kbMoveWinToWs=Super+Alt
kbMoveWinToWsGroup=Ctrl+Super+Alt
kbGoToWs=Super
kbGoToWsGroup=Ctrl+Super
kbNextWs=Ctrl+Super, right
kbPrevWs=Ctrl+Super, left
kbToggleSpecialWs=Super, S
kbWindowGroupCycleNext=Alt, Tab
kbWindowGroupCyclePrev=Shift+Alt, Tab
kbUngroup=Super, U
kbToggleGroup=Super, Comma
kbMoveWindow=Super, Z
kbResizeWindow=Super, X
kbWindowPip=Super+Alt, Backslash
kbPinWindow=Super, P
kbWindowFullscreen=Super, F
kbWindowBorderedFullscreen=Super+Alt, F
kbToggleWindowFloating=Super+Alt, Space
kbCloseWindow=Super, Q
kbSystemMonitor=Ctrl+Shift, Escape
kbMusic=Super, M
kbCommunication=Super, D
kbTodo=Super, R
kbTerminal=Super, T
kbBrowser=Super, W
kbEditor=Super, C
kbFileExplorer=Super, E
kbSession=Ctrl+Alt, Delete
kbShowSidebar=Super, N
kbClearNotifs=Ctrl+Alt, C
kbShowPanels=Super, K
kbLock=Super, L
kbRestoreLock=Super+Alt, L
"""
LEGACY_DEFAULTS = dict(
    line.split("=", 1) for line in LEGACY_DEFAULTS_TEXT.strip().splitlines() if line.strip()
)

RENAMED_VARS = {
    "kbToggleSpecialWs": "kbSpecialWs",
    # The old names were misleading: Alt+Tab cycled windows, not groups.
    "kbWindowGroupCycleNext": "kbWindowCycleNext",
    "kbWindowGroupCyclePrev": "kbWindowCyclePrev",
    "kbSystemMonitor": "kbSystemMonitorWs",
    "kbMusic": "kbMusicWs",
    "kbCommunication": "kbCommunicationWs",
    "kbTodo": "kbTodoWs",
}

SUPPORTED_VARS = {
    "terminal", "browser", "editor", "fileExplorer",
    "touchpadDisableTyping", "touchpadScrollFactor", "workspaceSwipeFingers",
    "gestureFingers", "gestureFingersMore",
    "blurEnabled", "blurSpecialWs", "blurPopups", "blurInputMethods",
    "blurSize", "blurPasses", "blurXray",
    "shadowEnabled", "shadowRange", "shadowRenderPower",
    "workspaceGaps", "windowGapsIn", "windowGapsOut", "singleWindowGapsOut",
    "windowOpacity", "windowRounding", "windowBorderSize",
    "volumeStep", "cursorTheme", "cursorSize",
    "kbMoveWinToWs", "kbMoveWinToWsGroup", "kbGoToWs", "kbGoToWsGroup",
    "kbNextWs", "kbPrevWs", "kbSpecialWs",
    "kbWindowCycleNext", "kbWindowCyclePrev", "kbUngroup", "kbToggleGroup",
    "kbMoveWindow", "kbResizeWindow", "kbWindowPip", "kbPinWindow",
    "kbWindowFullscreen", "kbWindowBorderedFullscreen", "kbToggleWindowFloating",
    "kbCloseWindow", "kbSystemMonitorWs", "kbMusicWs", "kbCommunicationWs",
    "kbTodoWs", "kbTerminal", "kbBrowser", "kbEditor", "kbFileExplorer",
    "kbSession", "kbShowSidebar", "kbClearNotifs", "kbShowPanels", "kbLock",
    "kbRestoreLock",
}

KEY_ALIASES = {
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "page_up": "Page_Up", "page_down": "Page_Down", "backslash": "Backslash",
    "delete": "Delete", "escape": "Escape", "space": "Space", "tab": "Tab",
    "return": "Return", "enter": "Return", "comma": "Comma", "period": "Period",
    "minus": "Minus", "equal": "Equal", "backspace": "Backspace",
}
MOD_ALIASES = {
    "super": "SUPER", "ctrl": "CTRL", "control": "CTRL", "alt": "ALT", "shift": "SHIFT",
}

VAR_RE = re.compile(r"^\s*\$(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<value>.*?)\s*(?:#.*)?$")
EXTRA_APP_BIND_RE = re.compile(
    r"^\s*bind\s*=\s*(?P<mods>[^,]*),\s*(?P<key>[^,]*),\s*exec\s*,\s*"
    r"app2unit\s+--\s+\$(?P<var>[A-Za-z_][A-Za-z0-9_]*)\s*(?:#.*)?$",
    re.IGNORECASE,
)

# Exec bindings that belonged to the managed legacy dotfiles. Unknown direct
# exec bindings are reported before the legacy tree is replaced, so local
# additions cannot disappear silently.
LEGACY_MANAGED_EXEC_PREFIXES = (
    "$wsaction ",
    "caelestia ",
    "qs -c caelestia ",
    "app2unit -- $terminal",
    "app2unit -- $browser",
    "app2unit -- $editor",
    "app2unit -- $fileExplorer",
    "app2unit -- github-desktop",
    "app2unit -- nemo",
    "app2unit -- qps",
    "app2unit -- pavucontrol",
    "hyprpicker -a",
    "wpctl ",
    "systemctl suspend-then-hibernate",
    "pkill fuzzel || caelestia ",
    "sleep 0.5s && ydotool ",
)
LEGACY_TEST_NOTIFICATION_PREFIX = (
    "notify-send -u low -i dialog-information-symbolic 'Test notification'"
)
SUPPORTED_BIND_FLAGS = {
    "l": "locked",
    "e": "repeating",
    "r": "release",
    "m": "mouse",
}


def xdg_path(env_name: str, fallback: str) -> Path:
    return Path(os.environ.get(env_name, str(Path.home() / fallback))).expanduser()


def parse_legacy_vars(path: Path) -> tuple[dict[str, str], list[str]]:
    values: dict[str, str] = {}
    unsupported: list[str] = []
    if not path.is_file():
        return values, unsupported

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = VAR_RE.match(raw)
        if match:
            values[match.group("name")] = match.group("value").strip()
        else:
            unsupported.append(raw)
    return values, unsupported


def normalise_keybind(value: str) -> str:
    if "," in value:
        mods, key = value.split(",", 1)
    else:
        mods, key = value, ""

    mod_parts = []
    for part in mods.split("+"):
        part = part.strip()
        if part:
            mod_parts.append(MOD_ALIASES.get(part.lower(), part.upper()))

    if not key:
        return " + ".join(mod_parts)

    key = key.strip()
    key = KEY_ALIASES.get(key.lower(), key)
    return " + ".join([*mod_parts, key])


def scalar_value(value: str) -> Any:
    lower = value.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False
    if re.fullmatch(r"[-+]?\d+", value):
        return int(value)
    if re.fullmatch(r"[-+]?(?:\d+\.\d*|\d*\.\d+)", value):
        return float(value)
    return value


def lua_literal(value: Any) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def collect_var_overrides(
    base_vars: dict[str, str], user_vars: dict[str, str], report: list[str]
) -> tuple[dict[str, Any], dict[str, str]]:
    overrides: dict[str, Any] = {}
    all_values = dict(base_vars)
    all_values.update(user_vars)

    # Base variables are managed defaults; keep only edits versus the old upstream defaults.
    candidates: dict[str, str] = {}
    for name, value in base_vars.items():
        default = LEGACY_DEFAULTS.get(name)
        if default is not None and value.strip() == default.strip():
            continue
        candidates[name] = value

    # hypr-vars.conf is explicitly a user override file, so keep all valid values from it.
    candidates.update(user_vars)

    for old_name, raw_value in candidates.items():
        new_name = RENAMED_VARS.get(old_name, old_name)
        if new_name not in SUPPORTED_VARS:
            # Extra command variables can still be consumed by custom bind migration.
            if old_name not in {"gituiclient"}:
                report.append(f"Untranslated variable: ${old_name} = {raw_value}")
            continue

        value: Any
        if new_name.startswith("kb"):
            value = normalise_keybind(raw_value)
        else:
            value = scalar_value(raw_value)
        overrides[new_name] = value

    return overrides, all_values


def write_hypr_vars(path: Path, overrides: dict[str, Any], report: list[str]) -> None:
    meaningful_existing = False
    if path.is_file():
        compact = "".join(line.strip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines())
        meaningful_existing = compact not in {"", "return{}", "return{};"}

    target = path
    if meaningful_existing:
        target = path.with_name("hypr-vars.migrated.lua")
        report.append(
            f"Kept existing {path}; wrote translated legacy overrides to {target} for manual merge."
        )

    lines = ["-- Generated by hyprblue-caelestia-migrate", "return {"]
    for key in sorted(overrides):
        lines.append(f"    {key} = {lua_literal(overrides[key])},")
    lines.append("}")
    lines.append("")
    target.write_text("\n".join(lines), encoding="utf-8")


def split_conf_csv(value: str, maxsplit: int | None = None) -> list[str]:
    if maxsplit is None:
        return [part.strip() for part in value.split(",")]
    return [part.strip() for part in value.split(",", maxsplit)]


def bind_flags_or_none(key: str, raw: str, report: list[str]) -> list[str] | None:
    """Return translated flags, or None when a bind suffix has unknown semantics."""
    suffix = key[4:]
    unknown = sorted(set(suffix) - set(SUPPORTED_BIND_FLAGS))
    if unknown:
        report.append(
            f"Untranslated hypr-user.conf bind flags {''.join(unknown)!r}: {raw}"
        )
        return None
    return [f"{SUPPORTED_BIND_FLAGS[ch]} = true" for ch in suffix]


def convert_user_conf(path: Path, report: list[str]) -> list[str]:
    if not path.is_file():
        return []

    converted: list[str] = ["-- Migrated from legacy hypr-user.conf"]
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw.strip()
        if not stripped:
            converted.append("")
            continue
        if stripped.startswith("#"):
            converted.append("--" + stripped[1:])
            continue

        key, sep, value = stripped.partition("=")
        if not sep:
            report.append(f"Untranslated hypr-user.conf line: {raw}")
            converted.append(f"-- TODO legacy: {raw}")
            continue
        key = key.strip().lower()
        value = value.strip()

        if key == "monitor":
            parts = split_conf_csv(value, 3)
            if len(parts) == 4:
                scale: Any = scalar_value(parts[3])
                converted.append(
                    "hl.monitor({ output = %s, mode = %s, position = %s, scale = %s })"
                    % tuple(lua_literal(v) for v in (parts[0], parts[1], parts[2], scale))
                )
                continue
        elif key in {"env", "envd"}:
            parts = split_conf_csv(value, 1)
            if len(parts) == 2:
                dbus = ", true" if key == "envd" else ""
                converted.append(f"hl.env({lua_literal(parts[0])}, {lua_literal(parts[1])}{dbus})")
                continue
        elif key == "exec":
            converted.append(f"hl.exec_cmd({lua_literal(value)})")
            continue
        elif key == "exec-once":
            converted.append(
                "hl.on(\"hyprland.start\", function() hl.exec_cmd(%s) end)" % lua_literal(value)
            )
            continue
        elif key.startswith("bind"):
            parts = split_conf_csv(value, 3)
            if len(parts) == 4 and parts[2].lower() == "exec":
                flags = bind_flags_or_none(key, raw, report)
                if flags is None:
                    converted.append(f"-- TODO legacy: {raw}")
                    continue
                bind_key = normalise_keybind(f"{parts[0]}, {parts[1]}")
                flag_arg = ", { " + ", ".join(flags) + " }" if flags else ""
                converted.append(
                    f"hl.bind({lua_literal(bind_key)}, hl.dsp.exec_cmd({lua_literal(parts[3])}){flag_arg})"
                )
                continue

        report.append(f"Untranslated hypr-user.conf line: {raw}")
        converted.append(f"-- TODO legacy: {raw}")

    converted.append("")
    return converted


def is_managed_legacy_exec(command: str) -> bool:
    return command.startswith(LEGACY_MANAGED_EXEC_PREFIXES) or command.startswith(
        LEGACY_TEST_NOTIFICATION_PREFIX
    )


def collect_legacy_keybinds(
    keybinds_path: Path, legacy_vars: dict[str, str], report: list[str]
) -> list[str]:
    """Migrate known custom app binds and report unknown direct exec binds."""
    if not keybinds_path.is_file():
        return []

    migrated: list[str] = []
    for raw in keybinds_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        match = EXTRA_APP_BIND_RE.match(raw)
        if match:
            var = match.group("var")
            # Default app bindings are generated from hypr-vars.lua.
            if var in {"terminal", "browser", "editor", "fileExplorer"}:
                continue
            command = legacy_vars.get(var)
            if not command:
                report.append(f"Could not migrate bind using unknown variable ${var}: {raw}")
                continue
            key = normalise_keybind(f"{match.group('mods')}, {match.group('key')}")
            migrated.append(f"hl.bind({lua_literal(key)}, hl.dsp.exec_cmd({lua_literal(command)}))")
            continue

        bind_name, sep, value = stripped.partition("=")
        bind_name = bind_name.strip().lower()
        if not sep or not bind_name.startswith("bind"):
            continue
        parts = split_conf_csv(value.strip(), 3)
        if len(parts) != 4 or parts[2].lower() != "exec":
            continue
        command = parts[3]
        if not is_managed_legacy_exec(command):
            report.append(f"Legacy direct exec bind not automatically migrated: {raw}")

    return migrated


def append_hypr_user(path: Path, statements: list[str]) -> None:
    if not statements:
        if not path.exists():
            path.write_text("", encoding="utf-8")
        return

    marker = "-- BEGIN hyprblue legacy migration"
    existing = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    if marker in existing:
        return

    block = [marker, *statements, "-- END hyprblue legacy migration", ""]
    with path.open("a", encoding="utf-8") as handle:
        if existing and not existing.endswith("\n"):
            handle.write("\n")
        handle.write("\n".join(block))


def migrate_shell_json(path: Path, report: list[str]) -> bool:
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        report.append(f"Could not migrate shell.json: {exc}")
        return False

    appearance = data.get("appearance")
    if not isinstance(appearance, dict):
        return False
    font = appearance.get("font")
    if not isinstance(font, dict):
        return False

    changed = False
    family = font.get("family")
    if isinstance(family, dict):
        clock = family.get("clock")
        sans = family.get("sans")
        mono = family.get("mono")
        material = family.get("material")

        if clock is not None and "clock" not in font:
            font["clock"] = clock
            changed = True
        if sans is not None:
            for style in ("headline", "title", "body", "label"):
                node = font.setdefault(style, {})
                if isinstance(node, dict) and "family" not in node:
                    node["family"] = sans
                    changed = True
        if mono is not None:
            node = font.setdefault("mono", {})
            if isinstance(node, dict) and "family" not in node:
                node["family"] = mono
                changed = True
        if material is not None:
            node = font.setdefault("icon", {})
            if isinstance(node, dict) and "family" not in node:
                node["family"] = material
                changed = True

        unknown_family = {
            key: value
            for key, value in family.items()
            if key not in {"clock", "sans", "mono", "material"}
        }
        if unknown_family:
            report.append(
                "Legacy shell font.family settings not translated: "
                + json.dumps(unknown_family, sort_keys=True, ensure_ascii=False)
            )
        del font["family"]
        changed = True

    size = font.get("size")
    if isinstance(size, dict):
        if "scale" in size and "scale" not in font:
            font["scale"] = size["scale"]
            changed = True

        unknown_size = {key: value for key, value in size.items() if key != "scale"}
        if unknown_size:
            # The original shell.json is already in the timestamped backup. Also
            # record the exact values here so removing the obsolete `size` object
            # from the new schema never loses them silently.
            report.append(
                "Legacy shell font.size settings not translated: "
                + json.dumps(unknown_size, sort_keys=True, ensure_ascii=False)
            )
        del font["size"]
        changed = True

    if changed:
        path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def backup_tree(src: Path, dst: Path) -> None:
    if not src.exists() and not src.is_symlink():
        return
    if src.is_symlink():
        # Dereference a legacy top-level config symlink so the backup stays usable
        # even if the old dotfiles checkout is later moved or deleted.
        resolved = src.resolve()
        if resolved.is_dir():
            shutil.copytree(resolved, dst, symlinks=True)
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(resolved, dst)
    elif src.is_dir():
        shutil.copytree(src, dst, symlinks=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst, follow_symlinks=False)


def replace_hypr_tree(config_home: Path) -> None:
    target = config_home / "hypr"
    tmp = config_home / ".hypr.caelestia-migrate"
    if tmp.exists():
        shutil.rmtree(tmp)
    shutil.copytree(SOURCE_HYPR, tmp, symlinks=True)
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.exists():
        shutil.rmtree(target)
    tmp.rename(target)


def detect_legacy(config_home: Path) -> bool:
    caelestia = config_home / "caelestia"
    return any(
        path.exists()
        for path in (
            config_home / "hypr" / "hyprland.conf",
            config_home / "hypr" / "variables.conf",
            caelestia / "hypr-vars.conf",
            caelestia / "hypr-user.conf",
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Preview or apply migration from legacy Caelestia Hyprlang config to the current Lua layout."
    )
    parser.add_argument("--apply", action="store_true", help="apply the migration (default is preview only)")
    args = parser.parse_args()

    config_home = xdg_path("XDG_CONFIG_HOME", ".config")
    state_home = xdg_path("XDG_STATE_HOME", ".local/state")
    hypr_dir = config_home / "hypr"
    caelestia_dir = config_home / "caelestia"

    if not SOURCE_HYPR.joinpath("hyprland.lua").is_file():
        print(f"error: current Caelestia Lua config not found at {SOURCE_HYPR}", file=sys.stderr)
        return 2

    if not detect_legacy(config_home):
        print("No legacy Caelestia Hyprlang config detected; nothing to migrate.")
        return 0

    base_vars, base_unparsed = parse_legacy_vars(hypr_dir / "variables.conf")
    user_vars, user_unparsed = parse_legacy_vars(caelestia_dir / "hypr-vars.conf")
    report: list[str] = []
    report.extend(f"Unparsed variables.conf line: {line}" for line in base_unparsed)
    report.extend(f"Unparsed hypr-vars.conf line: {line}" for line in user_unparsed)

    overrides, all_legacy_vars = collect_var_overrides(base_vars, user_vars, report)
    user_statements = convert_user_conf(caelestia_dir / "hypr-user.conf", report)
    user_statements.extend(
        collect_legacy_keybinds(hypr_dir / "hyprland" / "keybinds.conf", all_legacy_vars, report)
    )

    print("Legacy Caelestia config detected.")
    print(f"  Hypr overrides to migrate: {len(overrides)}")
    print(f"  User Lua statements generated: {sum(1 for line in user_statements if line and not line.startswith('--'))}")
    print("  shell.json: old font schema will be upgraded if present; transparency is left unchanged")
    if report:
        print(f"  Items requiring manual review: {len(report)}")

    if not args.apply:
        print("\nPreview only. Re-run with --apply to back up and migrate your config.")
        return 0

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = state_home / "hyprblue-caelestia" / "backups" / f"caelestia-legacy-{timestamp}"
    backup.mkdir(parents=True, exist_ok=False)
    backup_tree(hypr_dir, backup / "hypr")
    backup_tree(caelestia_dir, backup / "caelestia")

    caelestia_dir.mkdir(parents=True, exist_ok=True)
    write_hypr_vars(caelestia_dir / "hypr-vars.lua", overrides, report)
    append_hypr_user(caelestia_dir / "hypr-user.lua", user_statements)
    shell_changed = migrate_shell_json(caelestia_dir / "shell.json", report)
    replace_hypr_tree(config_home)

    report_path = backup / "migration-report.txt"
    report_text = [
        "hyprblue Caelestia legacy migration",
        f"Backup: {backup}",
        f"shell.json font schema changed: {shell_changed}",
        "",
    ]
    if report:
        report_text.extend(["Manual review:", *[f"- {item}" for item in report]])
    else:
        report_text.append("No untranslated legacy settings were detected.")
    report_path.write_text("\n".join(report_text) + "\n", encoding="utf-8")

    print(f"\nMigration complete. Backup: {backup}")
    print(f"Report: {report_path}")

    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
        proc = subprocess.run(["hyprctl", "reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if proc.returncode == 0:
            print("Hyprland config reloaded.")
        else:
            print("Hyprland reload failed; log out and back in to load the Lua config.")
    else:
        print("Log out and back in (or run `hyprctl reload`) to load the Lua config.")

    if report:
        print("Some legacy lines could not be translated automatically; see the report before deleting the backup.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
