#!/usr/bin/env bash
# One-command install of the toolkit:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/bluestero/unix-toolkit/main/bootstrap.sh)
#
# Clones it into ~/.local/share/unix-toolkit (or pulls, if it's already there), then
# runs ./install.sh, which asks before every change. Options:
#   --layer <git-url>   also add a layer first (a private repo needs your SSH key),
#                       so its parts are in the same checklist; repeat for several
#   --dir <folder>      put the toolkit somewhere else
# Anything else goes to install.sh (e.g. --dry-run, --plain).
set -euo pipefail

url="${TK_REPO:-https://github.com/bluestero/unix-toolkit.git}"
dir="${TK_DIR:-$HOME/.local/share/unix-toolkit}"
layers=() rest=()
while (( $# )); do
  case "$1" in
    --layer) layers+=("${2:?--layer needs a git URL}"); shift 2 ;;
    --dir)   dir="${2:?--dir needs a folder}"; shift 2 ;;
    *)       rest+=("$1"); shift ;;
  esac
done

command -v git >/dev/null || { echo "✗ git isn't installed (Ubuntu: sudo apt install git)" >&2; exit 1; }
if [[ -d $dir/.git ]]; then
  git -C "$dir" pull --ff-only -q && echo "✓ toolkit updated in ${dir/#$HOME/\~}"
else
  mkdir -p "$(dirname "$dir")"
  git clone -q "$url" "$dir" && echo "✓ toolkit cloned into ${dir/#$HOME/\~}"
fi

for l in "${layers[@]}"; do
  name=$(basename "${l%.git}"); name=${name%-toolkit}   # same name tk layer add gives it
  if [[ -d $dir/layers/$name/.git ]]; then
    git -C "$dir/layers/$name" pull --ff-only -q && echo "✓ layer $name updated"
  elif git clone -q "$l" "$dir/layers/$name"; then echo "✓ layer $name added"
  else echo "✗ couldn't clone $l (no access? check: ssh -T git@github.com); carrying on without it" >&2; fi
done

exec "$dir/install.sh" "${rest[@]}"
