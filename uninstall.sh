#!/usr/bin/env bash
# Removes parts of the work toolkit. Shows a checklist of what's installed;
# pick with space, confirm with enter. Safe to run any number of times.
# `./uninstall.sh help` lists the commands. Files that were replaced get their
# backup put back. Repo files are never deleted.
set -uo pipefail

repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
mode=ask details=0 list=0 help=0 layer=""
wanted=()
for arg in "$@"; do
  case "$arg" in
    ls|list)        list=1 ;;
    help|-h|--help) help=1 ;;
    -n|--dry-run)   mode=dry ;;
    -y|--yes)       mode=yes ;;
    -p|--plain)     export WORK_TOOLKIT_PLAIN=1 ;;
    --layer=*)      layer=${arg#--layer=} ;;
    -*) printf '✗ unknown option %s · see: ./uninstall.sh help\n' "$arg" >&2; exit 2 ;;
    *)  wanted+=("$arg") ;;
  esac
done

. "$repo/lib/setup.sh"
. "$repo/lib/components.sh"

if (( help )); then
  ui_help ./uninstall.sh "remove parts of the work toolkit" <<'EOF'
## Commands
./uninstall.sh	checklist of what's installed; pick what to remove
./uninstall.sh <component>...	just those, e.g. ./uninstall.sh zsh
./uninstall.sh ls	what's installed, so could be removed
./uninstall.sh help	this page

## Options
--dry-run	show what would be removed; changes nothing
--yes	no questions (components must be named)
--plain	don't use gum even if it's installed
--layer=<name>	only that layer's parts (fk uninstall uses it)

You get your own setup back: replaced files, the lines taken out of ~/.bashrc,
your default terminal, Ctrl+Alt+T and login shell. Repo files are never deleted.
What you had before: ~/.local/state/work-toolkit/originals
EOF
  exit 0
fi
use_gum

# What this run may touch: one layer's parts (--layer), else everything but standalone layers' (fk uninstall)
if [[ -n $layer ]]; then
  layer_path "$repo" "$layer" >/dev/null || { printf '✗ no layer %s · see: tk layer ls\n' "'$layer'" >&2; exit 2; }
  mapfile -t allowed < <(layer_parts "$layer")
else mapfile -t allowed < <(main_parts); fi
again=./install.sh
[[ -n $layer && -n ${STANDALONE[$layer]:-} ]] && again="${STANDALONE[$layer]} install"
for w in "${wanted[@]}"; do
  [[ " ${allowed[*]} " == *" $w "* ]] && continue
  if [[ " ${COMPONENTS[*]} " == *" $w "* ]]; then printf '✗ %s is removed with: %s %s\n' "'$w'" "$(setup_cmd "$w" | sed 's/ install$/ uninstall/; s/install.sh$/uninstall.sh/')" "$w" >&2
  else printf '✗ unknown command or component %s · see: ./install.sh ls\n' "'$w'" >&2; fi
  exit 2
done

# Only what's actually there can be removed.
present=() labels=()
for id in "${allowed[@]}"; do
  component_state "$id"
  [[ "$STATE" == installed || "$STATE" == partial ]] || continue
  present+=("$id")
  labels+=("$id"$'\t'"$("$(fn title "$id")")")
done

say ""
if (( ${#present[@]} == 0 )); then
  say "Nothing ${layer:+of $layer }is installed. Nothing to do."
  exit 0
fi

chosen=()
if (( ${#wanted[@]} )); then
  for w in "${wanted[@]}"; do
    if [[ " ${present[*]} " == *" $w "* ]]; then chosen+=("$w"); else say "  ${D}$w: not installed, skipping${R}"; fi
  done
elif dry || (( list )); then
  { printf '%s\n' "${B}COMPONENT${R}"$'\x1f'"${B}WHAT IT IS${R}"
    for l in "${labels[@]}"; do printf '%s\n' "${l%%$'\t'*}"$'\x1f'"$D${l#*$'\t'}$R"; done
  } | ui_table "work toolkit · installed" "${#present[@]} could be removed"
  exit 0
elif [[ "$mode" == yes ]]; then
  echo "--yes needs the components named, e.g.: ./uninstall.sh --yes zsh"; exit 2
else
  [[ -t 0 ]] || { echo "Run it in a terminal for the checklist, or name the components: ./uninstall.sh zsh"; exit 1; }
  checklist "Select what to remove:" "${labels[@]}" || { say "Cancelled. Nothing changed."; exit 0; }
  for i in "${CHECKLIST[@]}"; do chosen+=("${present[i]}"); done
fi
(( ${#chosen[@]} )) || { say "Nothing selected. Nothing changed."; exit 0; }

if dry; then
  say "Would remove: ${chosen[*]}"
  exit 0
fi
say ""
say "Removing: ${B}${chosen[*]}${R}"
ask "Go ahead?" || { say "Nothing changed."; exit 0; }

logf ""; logf "=== uninstall $ts ${chosen[*]}"
# login-shell before zsh, so the login shell is never left pointing at a removed zsh
order=()
[[ " ${chosen[*]} " == *" login-shell "* ]] && order+=(login-shell)
for id in "${chosen[@]}"; do [[ "$id" == login-shell ]] || order+=("$id"); done
for id in "${order[@]}"; do
  say "${B}$id${R}"
  "$(fn uninstall "$id")"
done

say ""
summary=""
for id in "${order[@]}"; do
  "$(fn state "$id")"
  if [[ "$STATE" == installed || "$STATE" == partial ]]; then summary+="${Y}◐${R} $("$(fn label "$id")")"$'\x1f'"${D}still partly there · see the log${R}"$'\n'
  else summary+="${G}✓${R} $("$(fn label "$id")")"$'\x1f'"${D}removed · $again $id puts it back${R}"$'\n'; fi
done
printf '%s' "$summary" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"
if [[ -t 1 ]]; then
  printf '%s' "$summary" | print_table 3 | ui_box "done" "open a new terminal to see the change" 0 "$(ui_hint "log: ${log_file/#$HOME/\~}")"
else
  printf '%s' "$summary" | print_table 3
fi
