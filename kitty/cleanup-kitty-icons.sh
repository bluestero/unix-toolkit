#!/usr/bin/env bash
# Removes the custom kitty icons and the user desktop entry (kitty goes back to
# its stock icon). Kitty itself and ~/.config/kitty are not touched.
# Safe to run any number of times.
set -Eeuo pipefail

ICON_DIR="$HOME/.local/share/icons/kitty-custom"
APP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APP_DIR/kitty.desktop"
BASHRC="$HOME/.bashrc"
changed=0

if [[ -d "$ICON_DIR" ]]; then rm -rf "$ICON_DIR"; echo "[REMOVED] $ICON_DIR"; changed=1
else echo "[OK] No custom icon folder"; fi

if [[ -f "$DESKTOP_FILE" ]]; then rm -f "$DESKTOP_FILE"; echo "[REMOVED] $DESKTOP_FILE"; changed=1
else echo "[OK] No user kitty desktop entry"; fi

# Old installs put a k-icon function into ~/.bashrc; the toolkit loads it from
# kitty/bin/k-icon instead, so remove any stray copy.
if [[ -f "$BASHRC" ]] && grep -qE '^# >>> Kitty Icon Picker >>>|^k-icon[[:space:]]*\(\)' "$BASHRC"; then
    cp -p "$BASHRC" "$BASHRC.bak-$(date +%Y%m%d-%H%M%S)"
    python3 -I - "$BASHRC" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
s = re.sub(r'(?ms)^# >>> Kitty Icon Picker >>>\s*\n.*?^# <<< Kitty Icon Picker <<<\s*\n?', '', s)
s = re.sub(r'(?ms)^k-icon\s*\(\)\s*\{.*?^\}\s*\n?', '', s)
p.write_text(s)
PY
    echo "[REMOVED] old k-icon function from ~/.bashrc"
    changed=1
fi

if ((changed)) && command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APP_DIR" 2>/dev/null || true
fi
if ((changed)); then echo "[DONE] Custom kitty icons removed."
else echo "[DONE] Nothing to remove."; fi
