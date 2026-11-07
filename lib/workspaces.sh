# The workspace lists. Sourced by ws, the installer and layer commands.
#
#   layers/<name>/workspaces  a team's shared list, from a layer (lib/layers.sh);
#                             in the layer's repo, so updates bring new entries
#   ~/.config/ws/workspaces   your own list, outside the repo; updates never touch it.
#                             An "@<name>" line pulls in layer <name>'s list there.
# With no personal list yet, every layer's list together is the list.
#
# A line NAME=folder (capitals) sets a variable the paths can use as $NAME, e.g.
# ACME=~/work/acme then $ACME/api. Layers set defaults; the
# same line in your own list wins.
#
#   ws_list               one line per workspace: <path><TAB><owner/repo or empty>
#   ws_var <NAME>         a variable's folder (expanded), e.g. ws_var ACME
#   ws_list_file          your list's path (it may not exist yet)
#   ws_personal_init      create your list from the template if it's missing; prints its path

_WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=layers.sh
. "$_WS_ROOT/lib/layers.sh"
ws_list_file() { printf '%s' "${WS_LIST_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/ws/workspaces}"; }
# every layer's shared list: <name><TAB><file>
_ws_layer_lists() {
  local d
  while IFS= read -r d; do
    [[ -r $d/workspaces ]] && printf '%s\t%s\n' "$(basename "$d")" "$d/workspaces"
  done < <(layer_dirs "$_WS_ROOT")
}

# meaningful lines of a list file (comments and blanks dropped)
_ws_lines() {
  local line
  [[ -r $1 ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -n $line ]] && printf '%s\n' "$line"
  done <"$1"
}

_ws_is_var() { [[ $1 =~ ^[A-Z_][A-Z0-9_]*= ]]; }

_ws_expand() {
  local p="$1" k
  for k in "${!_WS_VARS[@]}"; do p="${p//\$\{$k\}/${_WS_VARS[$k]}}"; p="${p//\$$k/${_WS_VARS[$k]}}"; done
  [[ $p == "~"* ]] && p="$HOME${p:1}"
  printf '%s' "${p%/}"
}

_ws_read() {
  local mine line f name seen=$'\n'
  local -a raw=() a=() lists=()
  declare -gA _WS_VARS=(); _WS_LINES=()
  mine=$(ws_list_file)
  mapfile -t lists < <(_ws_layer_lists)
  # 1. variables: the layers' defaults, then yours
  for f in "${lists[@]#*$'\t'}" "$mine"; do
    while IFS= read -r line; do
      _ws_is_var "$line" || continue
      name=${line%%=*}; line=${line#*=}
      [[ $line == "~"* ]] && line="$HOME${line:1}"
      _WS_VARS[$name]=${line%/}
    done < <(_ws_lines "$f")
  done
  # 2. the entries: your list (with @<layer> expanded), or every layer's if you have none
  if [[ -r $mine ]]; then
    while IFS= read -r line; do
      if [[ $line == @* ]]; then
        for f in "${lists[@]}"; do
          [[ ${f%%$'\t'*} == "${line#@}" ]] && mapfile -t -O "${#raw[@]}" raw < <(_ws_lines "${f#*$'\t'}")
        done
      else raw+=("$line"); fi
    done < <(_ws_lines "$mine")
  else
    for f in "${lists[@]}"; do mapfile -t -O "${#raw[@]}" raw < <(_ws_lines "${f#*$'\t'}"); done
  fi
  for line in "${raw[@]}"; do
    [[ $line == @* ]] && continue
    _ws_is_var "$line" && continue
    read -r -a a <<<"$line"
    f=$(_ws_expand "${a[0]}")
    [[ $seen == *$'\n'"$f"$'\n'* ]] && continue   # listed twice: keep the first
    seen+="$f"$'\n'
    _WS_LINES+=("$f"$'\t'"${a[1]:-}")
  done
}

ws_var() { _ws_read; printf '%s' "${_WS_VARS[$1]:-}"; }
ws_vars() { _ws_read; (( ${#_WS_VARS[@]} )) && printf '%s\n' "${!_WS_VARS[@]}" | sort; }
ws_list() { _ws_read; (( ${#_WS_LINES[@]} )) && printf '%s\n' "${_WS_LINES[@]}"; }

# ws_set_var NAME <folder>: save NAME=<folder> in your list (replacing its line
# there, or adding one at the top), so every tool sees the new folder.
ws_set_var() {
  local mine v; mine=$(ws_personal_init)
  v=${2/#$HOME/\~}
  if grep -q "^[[:space:]]*$1=" "$mine"; then
    NAME=$1 V=$v awk '{ if (!done && $0 ~ "^[[:space:]]*" ENVIRON["NAME"] "=") { print ENVIRON["NAME"] "=" ENVIRON["V"]; done=1 } else print }' \
      "$mine" >"$mine.tmp" && mv "$mine.tmp" "$mine"
  else
    printf '%s=%s\n%s\n' "$1" "$v" "$(cat "$mine")" >"$mine"
  fi
}

ws_personal_init() {
  local mine l name file; mine=$(ws_list_file)
  if [[ ! -e $mine ]]; then
    mkdir -p "$(dirname "$mine")"
    {
      cat <<'EOF'
# Your workspaces: ws opens these, and ./install.sh repos clones the missing ones.
# This file is yours: it lives outside the toolkit repo, so updates never change it.
#
#   <folder>   [<github owner/repo>]     (no repo = just a folder, never cloned)
EOF
      while IFS=$'\t' read -r name file; do
        printf '\n# From the %s layer (layers/%s/workspaces), kept up to date by tk update.\n' "$name" "$name"
        while IFS= read -r l; do
          _ws_is_var "$l" && printf '# Where its repos go: change it here to keep them elsewhere.\n%s\n' "$l"
        done < <(_ws_lines "$file")
        printf '# Delete this line to leave its repos out.\n@%s\n' "$name"
      done < <(_ws_layer_lists)
      cat <<'EOF'

# Your own folders and repos, for example:
# ~/code/my-project        me/my-project
# ~/notes
EOF
    } >"$mine"
  fi
  printf '%s' "$mine"
}
