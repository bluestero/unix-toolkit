#!/usr/bin/env bash
# Gets the toolkit onto a machine:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/bluestero/unix-toolkit/main/bootstrap.sh)
#
# Clones it into ~/.local/share/unix-toolkit (or pulls, if it's already there) and
# puts the tk command in ~/.local/bin. Nothing else changes: `tk install` then
# shows the checklist. --dir <folder> puts the toolkit somewhere else.
#
# --layer <name or git URL> also adds a layer (repeat it for more): feelkit (the
# appearance parts) by name, any other layer by its git URL. Example:
#   bash <(curl -fsSL .../bootstrap.sh) --layer feelkit
set -euo pipefail

url="${TK_REPO:-https://github.com/bluestero/unix-toolkit.git}"
dir="${TK_DIR:-$HOME/.local/share/unix-toolkit}"
layers=()
while (( $# )); do
  case "$1" in
    --dir)     dir="${2:?--dir needs a folder}"; shift 2 ;;
    --layer)   layers+=("${2:?--layer needs a name or a git URL}"); shift 2 ;;
    --layer=*) layers+=("${1#--layer=}"); shift ;;
    *)         echo "✗ unknown option: $1 (--dir <folder>, --layer <name or git URL>)" >&2; exit 1 ;;
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

# layers: feelkit by name; anything else is a git URL. `tk layer add` offers to set up its parts.
for l in "${layers[@]}"; do
  [[ $l == feelkit ]] && l=https://github.com/bluestero/unix-feelkit.git
  name=$(basename "${l%.git}"); name=${name#unix-}; name=${name%-toolkit}
  if [[ -d $dir/layers/$name ]]; then echo "✓ layer $name already there"
  else echo; "$dir/bin/tk" layer add "$l" || echo "✗ couldn't add the layer $l (see above)" >&2; fi
done

echo
case ":$PATH:" in
  *":$HOME/.local/bin:"*) echo "Next: tk install" ;;
  *) echo "Next: ~/.local/bin/tk install   (plain \`tk\` works once you open a new terminal after installing)" ;;
esac
