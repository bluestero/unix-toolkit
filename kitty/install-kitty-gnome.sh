#!/usr/bin/env bash
# Kitty + GNOME: kitty as the default terminal (Ctrl+Alt+T), and "Open in
# Terminal" / Ctrl+Shift+Enter in Files (nautilus-open-any-terminal).
# Safe to run any number of times: each step checks first and skips if done.
# Undo: ./uninstall-kitty-gnome.sh (or ../uninstall.sh kitty-nautilus)
set -Eeuo pipefail

REPO_URL="https://github.com/Stunkymonkey/nautilus-open-any-terminal.git"
REPO_DIR="$HOME/nautilus-open-any-terminal"
SCHEMA_DIR="$HOME/.local/share/glib-2.0/schemas"
SCHEMA_ID="com.github.stunkymonkey.nautilus-open-any-terminal"
EXT_FILE="$HOME/.local/share/nautilus-python/extensions/nautilus_open_any_terminal.py"
changed=0

as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
# Your settings before the first change, so the uninstall puts back yours (not
# the system default). Same file as ../lib/setup.sh uses; kept once, never overwritten.
ORIG_SETTINGS="$HOME/.local/state/work-toolkit/originals/settings"
remember() {
    mkdir -p "$(dirname "$ORIG_SETTINGS")"
    grep -q "^$1=" "$ORIG_SETTINGS" 2>/dev/null || printf '%s=%s\n' "$1" "$2" >>"$ORIG_SETTINGS"
}

command -v apt-get >/dev/null || { echo "[ERROR] Needs Ubuntu/Debian."; exit 1; }
command -v kitty >/dev/null || { echo "[ERROR] Kitty is not installed. Install it first."; exit 1; }
KITTY=$(readlink -f "$(command -v kitty)")
# the official build (../install.sh kitty) wins over Ubuntu's
if [[ -x "$HOME/.local/kitty.app/bin/kitty" ]]; then KITTY="$HOME/.local/kitty.app/bin/kitty"
elif [[ -x /usr/bin/kitty ]]; then KITTY=/usr/bin/kitty; fi

# --- packages (installs only what's missing)
PACKAGES=(git make gettext python3-nautilus gir1.2-gtk-4.0 libglib2.0-bin)
MISSING=()
for p in "${PACKAGES[@]}"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == "install ok installed" ]] || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
    echo "[INSTALLING] ${MISSING[*]} (sudo)"
    as_root apt-get install -y "${MISSING[@]}" || { as_root apt-get update && as_root apt-get install -y "${MISSING[@]}"; }
else
    echo "[OK] Packages"
fi

# --- extension source
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "[OK] Source in $REPO_DIR"
elif [[ -e "$REPO_DIR" ]]; then
    echo "[ERROR] $REPO_DIR exists but isn't a git checkout. Move it and run again."
    exit 1
else
    echo "[DOWNLOADING] nautilus-open-any-terminal"
    git clone -q "$REPO_URL" "$REPO_DIR"
fi

# --- build + install (only if missing or out of date)
SRC="$REPO_DIR/nautilus_open_any_terminal/nautilus_open_any_terminal.py"
if [[ -f "$EXT_FILE" && -f "$SCHEMA_DIR/$SCHEMA_ID.gschema.xml" ]] && cmp -s "$SRC" "$EXT_FILE"; then
    echo "[OK] Nautilus extension installed"
else
    echo "[INSTALLING] Nautilus extension"
    make -s -C "$REPO_DIR" >/dev/null
    make -s -C "$REPO_DIR" install-nautilus >/dev/null
    changed=1
fi

# --- settings schema
# (grep reads a saved copy: 'cmd | grep -q' can fail at random under pipefail)
have_schema() { grep -Fxq "$SCHEMA_ID" <<<"$(gsettings list-schemas)"; }
if have_schema && ((changed == 0)); then
    echo "[OK] Settings schema"
else
    mkdir -p "$SCHEMA_DIR"
    glib-compile-schemas "$SCHEMA_DIR"
    have_schema || { echo "[ERROR] Schema not available to GSettings."; exit 1; }
    echo "[COMPILED] Settings schema"
fi

# --- Files: open kitty, Ctrl+Shift+Enter
set_key() {
    if [[ "$(gsettings get "$SCHEMA_ID" "$1")" == "'$2'" ]]; then echo "[OK] $1 = $2"
    else gsettings set "$SCHEMA_ID" "$1" "$2"; echo "[SET] $1 = $2"; changed=1; fi
}
# (this extension is new, so its settings have no "before" to remember)
set_key terminal kitty
set_key keybindings '<Ctrl><Shift>Return'

# --- system default terminal
ALT_Q=$(update-alternatives --query x-terminal-emulator 2>/dev/null || true)
ALT_V=$(sed -n 's/^Value: //p' <<<"$ALT_Q")
# (a manual kitty is this script's own doing from an earlier run, so not yours)
if ! grep -q '^Status: manual' <<<"$ALT_Q"; then remember x-terminal-emulator auto
elif [[ "$ALT_V" != *kitty* ]]; then remember x-terminal-emulator "$ALT_V"; fi
if ! grep -Fxq "$KITTY" <<<"$(update-alternatives --list x-terminal-emulator 2>/dev/null)"; then
    as_root update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$KITTY" 20
fi
if [[ "$(update-alternatives --query x-terminal-emulator 2>/dev/null | sed -n 's/^Value: //p')" == "$KITTY" ]]; then
    echo "[OK] Kitty is the default terminal"
else
    as_root update-alternatives --set x-terminal-emulator "$KITTY"
    echo "[SET] Kitty is the default terminal"
fi

# --- Ctrl+Alt+T focuses kitty (kitty/bin/kitty-focus); Ctrl+Shift+Alt+T opens a new window
MK=org.gnome.settings-daemon.plugins.media-keys
KF_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty-focus/
KF_SCHEMA="$MK.custom-keybinding:$KF_PATH"
KF_CMD="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/bin/kitty-focus"
if command -v gsettings >/dev/null && gsettings list-keys "$MK" 2>/dev/null | grep -qx terminal; then
    kf_set() { [[ "$(gsettings get "$1" "$2")" == "$3" ]] || { gsettings set "$1" "$2" "$3"; kf_changed=1; }; }
    kf_changed=0
    [[ "$(gsettings get "$MK" terminal)" == "['<Primary><Shift><Alt>t']" ]] ||
        remember media-keys-terminal "$(gsettings get "$MK" terminal)"
    kf_set "$MK" terminal "['<Primary><Shift><Alt>t']"
    kf_set "$KF_SCHEMA" name "'Focus kitty'"
    kf_set "$KF_SCHEMA" command "'$KF_CMD'"
    kf_set "$KF_SCHEMA" binding "'<Primary><Alt>t'"
    list=$(gsettings get "$MK" custom-keybindings)
    if [[ $list != *"'$KF_PATH'"* ]]; then
        list=$(python3 -I -c 'import ast,sys; l=ast.literal_eval(sys.argv[1].removeprefix("@as ")); print(l+[sys.argv[2]])' "$list" "$KF_PATH")
        gsettings set "$MK" custom-keybindings "$list"; kf_changed=1
    fi
    if ((kf_changed)); then echo "[SET] Ctrl+Alt+T focuses kitty, Ctrl+Shift+Alt+T opens a new window"
    else echo "[OK] Ctrl+Alt+T focuses kitty, Ctrl+Shift+Alt+T opens a new window"; fi
fi

if ((changed)); then
    nautilus -q 2>/dev/null || true
    echo "[DONE] Reopen Files to use it: right-click > Open in Terminal, or Ctrl+Shift+Enter."
else
    echo "[DONE] Already set up, nothing changed."
fi
