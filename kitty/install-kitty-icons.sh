#!/usr/bin/env bash
# Kitty custom icons (DinkDonk dark/light + the default) and the user desktop
# entry that k-icon switches between. Safe to run any number of times: only
# missing pieces are added, and your current icon choice is kept.
#
# The k-icon command itself is kitty/bin/k-icon.
# Undo: ./cleanup-kitty-icons.sh (or ../uninstall.sh kitty-icons)
set -Eeuo pipefail

ICON_DIR="$HOME/.local/share/icons/kitty-custom"
APP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APP_DIR/kitty.desktop"
BASE_URL="https://raw.githubusercontent.com/DinkDonk/kitty-icon/main"
changed=0

# The official build (../install.sh kitty) wins over Ubuntu's.
KITTY_APP="$HOME/.local/kitty.app"
echo "[CHECK] Kitty..."
if [[ -f "$KITTY_APP/share/applications/kitty.desktop" ]]; then SRC_DESKTOP="$KITTY_APP/share/applications/kitty.desktop"
elif [[ -f /usr/share/applications/kitty.desktop ]]; then SRC_DESKTOP=/usr/share/applications/kitty.desktop
else
    echo "[ERROR] Kitty desktop entry not found. Install Kitty first."
    exit 1
fi

# --- dependencies (installs only what's missing)
PACKAGES=(fzf curl file desktop-file-utils)
MISSING=()
for package in "${PACKAGES[@]}"; do
    [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == "install ok installed" ]] || MISSING+=("$package")
done
if ((${#MISSING[@]})); then
    echo "[INSTALLING] ${MISSING[*]} (sudo)"
    if [[ $EUID -eq 0 ]]; then APT=(apt-get); else APT=(sudo apt-get); fi
    "${APT[@]}" install -y "${MISSING[@]}" || { "${APT[@]}" update && "${APT[@]}" install -y "${MISSING[@]}"; }
else
    echo "[OK] Dependencies: ${PACKAGES[*]}"
fi

# --- icons (downloads only missing or broken ones)
mkdir -p "$ICON_DIR"
download_icon() {
    local name="$1" source="$2" destination="$ICON_DIR/$1.png"
    if [[ -f "$destination" ]] && [[ "$(file -b "$destination")" == PNG\ image* ]]; then
        echo "[OK] $name.png"
        return
    fi
    echo "[DOWNLOADING] $name.png"
    curl -fLsS "$source" -o "$destination.tmp" || { rm -f "$destination.tmp"; echo "[ERROR] Download failed: $name.png"; exit 1; }
    [[ "$(file -b "$destination.tmp")" == PNG\ image* ]] || { rm -f "$destination.tmp"; echo "[ERROR] Not a PNG: $name.png"; exit 1; }
    mv "$destination.tmp" "$destination"
    changed=1
}
download_icon "dinkdonk-dark"  "$BASE_URL/kitty-dark.png"
download_icon "dinkdonk-light" "$BASE_URL/kitty-light.png"
download_icon "default"        "https://raw.githubusercontent.com/kovidgoyal/kitty/master/logo/kitty.png"

# --- user desktop entry (created once; the icon you picked is kept)
mkdir -p "$APP_DIR"
if [[ ! -f "$DESKTOP_FILE" ]]; then
    cp "$SRC_DESKTOP" "$DESKTOP_FILE"
    [[ "$SRC_DESKTOP" == "$KITTY_APP"/* ]] && sed -i -E "s#^(Try)?Exec=kitty( |$)#\1Exec=$KITTY_APP/bin/kitty\2#" "$DESKTOP_FILE"
    echo "[CREATED] $DESKTOP_FILE"
    changed=1
fi
CURRENT_ICON=$(grep -m1 '^Icon=' "$DESKTOP_FILE" | cut -d= -f2- || true)
if [[ -z "$CURRENT_ICON" || "$CURRENT_ICON" == kitty || ! -f "$CURRENT_ICON" ]]; then
    sed -i "s|^Icon=.*|Icon=$ICON_DIR/dinkdonk-dark.png|" "$DESKTOP_FILE"
    echo "[SET] Icon: dinkdonk-dark"
    changed=1
else
    echo "[OK] Icon: $(basename "$CURRENT_ICON" .png)"
fi

if ((changed)); then
    update-desktop-database "$APP_DIR"
    echo "[DONE] Kitty icons set up. Pick one with: k-icon"
else
    echo "[DONE] Already set up, nothing changed. Pick an icon with: k-icon"
fi
