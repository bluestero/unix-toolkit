#!/usr/bin/env bash
# Undoes install-kitty-gnome.sh: removes the Files extension and its settings,
# and lets the system pick the default terminal again. Kitty stays installed.
# Safe to run any number of times.
set -Euo pipefail

REPO_DIR="$HOME/nautilus-open-any-terminal"
SCHEMA_DIR="$HOME/.local/share/glib-2.0/schemas"
SCHEMA_ID="com.github.stunkymonkey.nautilus-open-any-terminal"
EXT_FILE="$HOME/.local/share/nautilus-python/extensions/nautilus_open_any_terminal.py"
changed=0

as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
# What you had before install-kitty-gnome.sh (it keeps it here), so yours comes back.
ORIG_SETTINGS="$HOME/.local/state/work-toolkit/originals/settings"
recall() { sed -n "s/^$1=//p" "$ORIG_SETTINGS" 2>/dev/null | head -1; }
forget() { [[ -f "$ORIG_SETTINGS" ]] && sed -i "/^$1=/d" "$ORIG_SETTINGS"; return 0; }

if [[ -f "$EXT_FILE" || -f "$SCHEMA_DIR/$SCHEMA_ID.gschema.xml" ]]; then
    gsettings reset-recursively "$SCHEMA_ID" 2>/dev/null || true
    if [[ -d "$REPO_DIR/.git" ]]; then
        make -s -C "$REPO_DIR" uninstall-nautilus >/dev/null 2>&1 || true
    fi
    rm -f "$EXT_FILE" "$SCHEMA_DIR/$SCHEMA_ID.gschema.xml"
    glib-compile-schemas "$SCHEMA_DIR" 2>/dev/null || true
    echo "[REMOVED] Files extension and its settings"
    changed=1
else
    echo "[OK] Files extension not installed"
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    rm -rf "$REPO_DIR"
    echo "[REMOVED] $REPO_DIR (downloaded source)"
fi

PREV_TERM=$(recall x-terminal-emulator)
CUR_Q=$(update-alternatives --query x-terminal-emulator 2>/dev/null || true)
if [[ -n "$PREV_TERM" && "$PREV_TERM" != auto ]] && grep -Fxq "$PREV_TERM" <<<"$(update-alternatives --list x-terminal-emulator 2>/dev/null)"; then
    if [[ "$(sed -n 's/^Value: //p' <<<"$CUR_Q")" != "$PREV_TERM" ]]; then
        as_root update-alternatives --set x-terminal-emulator "$PREV_TERM" >/dev/null
        echo "[RESET] Default terminal: back to yours ($PREV_TERM)"
        changed=1
    else
        echo "[OK] Default terminal is already yours ($PREV_TERM)"
    fi
elif grep -q '^Status: manual' <<<"$CUR_Q"; then
    as_root update-alternatives --auto x-terminal-emulator >/dev/null
    echo "[RESET] Default terminal: back to the system's choice ($(update-alternatives --query x-terminal-emulator | sed -n 's/^Value: //p'))"
    changed=1
else
    echo "[OK] Default terminal is already the system's choice"
fi
forget x-terminal-emulator

MK=org.gnome.settings-daemon.plugins.media-keys
KF_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty-focus/
list=$(gsettings get "$MK" custom-keybindings 2>/dev/null)
if [[ $list == *"'$KF_PATH'"* ]]; then
    list=$(python3 -I -c 'import ast,sys; l=ast.literal_eval(sys.argv[1].removeprefix("@as ")); print([p for p in l if p != sys.argv[2]])' "$list" "$KF_PATH")
    gsettings set "$MK" custom-keybindings "$list"
    gsettings reset-recursively "$MK.custom-keybinding:$KF_PATH" 2>/dev/null || true
    PREV_KEY=$(recall media-keys-terminal)
    if [[ -n "$PREV_KEY" ]]; then gsettings set "$MK" terminal "$PREV_KEY"; else gsettings reset "$MK" terminal; fi
    forget media-keys-terminal
    echo "[RESET] Ctrl+Alt+T opens a new terminal again"
else
    echo "[OK] Ctrl+Alt+T focus key not set"
fi

((changed)) && { nautilus -q 2>/dev/null || true; }
echo "[DONE]"
