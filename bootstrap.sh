#!/usr/bin/env bash
# Gets the toolkit onto a machine:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/bluestero/unix-toolkit/main/bootstrap.sh)
#
# Clones it into ~/.local/share/unix-toolkit (or pulls, if it's already there) and
# puts the tk command in ~/.local/bin. Nothing else changes: `tk install` then
# shows the checklist. --dir <folder> puts the toolkit somewhere else.
set -euo pipefail

url="${TK_REPO:-https://github.com/bluestero/unix-toolkit.git}"
dir="${TK_DIR:-$HOME/.local/share/unix-toolkit}"
while (( $# )); do
  case "$1" in
    --dir) dir="${2:?--dir needs a folder}"; shift 2 ;;
    *)     echo "✗ unknown option: $1 (only --dir <folder>)" >&2; exit 1 ;;
  esac
done
dir=$(realpath -m -- "$dir")

command -v git >/dev/null || { echo "✗ git isn't installed (Ubuntu: sudo apt install git)" >&2; exit 1; }
if [[ -d $dir/.git ]]; then
  git -C "$dir" pull --ff-only -q && echo "✓ toolkit updated in ${dir/#$HOME/\~}"
else
  mkdir -p "$(dirname "$dir")"
  git clone -q "$url" "$dir" && echo "✓ toolkit cloned into ${dir/#$HOME/\~}"
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$dir/bin/tk" "$HOME/.local/bin/tk" && echo "✓ tk command in ~/.local/bin"

echo
case ":$PATH:" in
  *":$HOME/.local/bin:"*) echo "Next: tk install" ;;
  *) echo "Next: ~/.local/bin/tk install   (plain \`tk\` works once you open a new terminal after installing)" ;;
esac
