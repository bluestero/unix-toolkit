#!/usr/bin/env bash
# Sets up the work toolkit on this machine. Safe to run any number of times:
# it checks what's already in place and only asks about what isn't.
# `./install.sh help` lists the commands. Undo any part with ./uninstall.sh.
# Log: ~/.local/state/work-toolkit/setup.log
set -uo pipefail

repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
mode=ask details=0 list=0 help=0
wanted=()
for arg in "$@"; do
  case "$arg" in
    ls|list)        list=1 ;;
    help|-h|--help) help=1 ;;
    -n|--dry-run)   mode=dry ;;
    -y|--yes)       mode=yes ;;
    -d|--details)   details=1 ;;
    -p|--plain)     export WORK_TOOLKIT_PLAIN=1 ;;
    -*) printf '✗ unknown option %s · see: ./install.sh help\n' "$arg" >&2; exit 2 ;;
    *)  wanted+=("$arg") ;;
  esac
done

setup_phase=install   # lets lib/setup.sh keep your originals (see "originals" there)
. "$repo/lib/setup.sh"
. "$repo/lib/components.sh"

if (( help )); then
  ui_help ./install.sh "set up the work toolkit" <<'EOF'
## Commands
./install.sh	checklist of what's missing, then one question per change	Enter = yes
./install.sh <component>...	just those, e.g. ./install.sh zsh
./install.sh ls	every component and whether it's installed
./install.sh help	this page

## Options
--dry-run	show what would change; changes nothing
--details	also show diffs (e.g. ~/.bashrc) before asking
--yes	no questions, for scripted setups
--plain	don't use or offer gum (the nicer-looking lists)

./install.sh ls names every component; ./uninstall.sh undoes any of them.
Log: ~/.local/state/work-toolkit/setup.log
EOF
  exit 0
fi

for w in "${wanted[@]}"; do
  [[ " ${COMPONENTS[*]} " == *" $w "* ]] || { printf '✗ unknown command or component %s · see: ./install.sh ls\n' "'$w'" >&2; exit 2; }
done
named=${#wanted[@]}
(( named )) || wanted=("${COMPONENTS[@]}")

if [[ "$mode" == ask && $list == 0 && ! -t 0 ]]; then
  echo "This installer asks before each change, but there's no terminal to ask in."
  echo "Run it in a terminal, or use --dry-run to preview / --yes to accept everything. (./install.sh ls just lists.)"
  exit 1
fi

badge() {
  case "$1" in
    installed) printf '%s✓ installed%s' "$G" "$R" ;;
    partial)   printf '%s◐ partly%s' "$Y" "$R" ;;
    missing)   printf '%s○ not installed%s' "$Y" "$R" ;;
    unsupported) printf '%s⊘ not supported here%s' "$D" "$R" ;;
    *)         printf '%s– n/a%s' "$D" "$R" ;;
  esac
}

logf ""; logf "=== install $ts ($mode) ${wanted[*]}"
# Overview: every component and its state, grouped, in one box.
todo=() prev="" table=""
table+="${B}COMPONENT${R}"$'\x1f'"${B}STATE${R}"$'\x1f'"${B}NOTE${R}"$'\n'
skipped=0
for id in "${wanted[@]}"; do
  component_state "$id"
  [[ "$STATE" == unsupported ]] && (( skipped++ ))
  if (( ! named )) && [[ "$(group_of "$id")" != "$prev" ]]; then
    [[ -n "$prev" ]] && table+=$'\n'
    prev=$(group_of "$id"); table+="${D}$prev${R}"$'\n'
  fi
  table+="  $id"$'\x1f'"$(badge "$STATE")"$'\x1f'"$D${NOTE}$R"$'\n'
  [[ "$STATE" == missing || "$STATE" == partial ]] && todo+=("$id")
  # login-shell depends on zsh: if zsh is about to be installed, offer it too
  [[ "$id" == login-shell && "$STATE" == n/a && " ${todo[*]} " == *" zsh "* ]] && todo+=("$id")
done
say ""
if (( ${#todo[@]} )); then right="${#todo[@]} to set up"; else right="${G}all set${R}"; fi
printf '%s' "$table" | ui_table "work toolkit" "$right"
printf '%s' "$table" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"
# Which machine this is, and what that rules out (the reasons are in the NOTE column).
say "${D}This machine: $OS_NAME · $DESKTOP_NAME · ${PKG_MGR/none/no package manager}${R}"
(( skipped )) && say "${D}$skipped component(s) can't run here and are skipped (⊘ above, with the reason).${R}"
(( list )) && exit 0
say ""
if (( ${#todo[@]} == 0 )); then
  if (( skipped == ${#wanted[@]} )); then say "None of these can run on this machine. Nothing to do."
  else say "Everything is already set up. Nothing to do."; fi
  exit 0
fi

# Use gum when it's there. Only a full setup (no components named) offers to
# download it; "./install.sh window-calls" and the like just use the plain look.
if [[ "$mode" == ask && "${WORK_TOOLKIT_PLAIN:-0}" != 1 ]] && use_gum; then
  (( named )) || { say "${G}✓${R} gum is installed, so the lists and questions use it ${D}(--plain for the plain ones)${R}"; say ""; }
elif [[ "$mode" == ask && "${WORK_TOOLKIT_PLAIN:-0}" != 1 && $named == 0 ]]; then
  if ask "Install gum for a nicer-looking installer? (small download to ~/.local/bin, no sudo)"; then
    if install_gum && use_gum; then ok "gum installed"
    else warn "carrying on with the plain installer"; fi
  else
    say "      ${D}OK, plain installer. (--plain skips this question)${R}"
  fi
  say ""
fi

# Pick what to set up (all ticked; untick with space). Named components or
# --yes / --dry-run skip the list.
if [[ "$mode" == ask && $named == 0 ]]; then
  say "Everything below is ticked, so ${B}Enter${R} sets it all up. Untick anything you don't want."
  say "${D}Each change still asks first (Enter = yes), and ./uninstall.sh undoes any of it.${R}"
  say ""
  labels=() ids=() on="" prev=""
  for id in "${todo[@]}"; do
    if [[ "$(group_of "$id")" != "$prev" ]]; then
      prev=$(group_of "$id"); labels+=("## $prev"); ids+=("")
    fi
    on+="${#labels[@]} "
    labels+=("$id"$'\t'"$("$(fn title "$id")")"); ids+=("$id")
  done
  CHECKLIST_ON=$on checklist "Pick what to set up:" "${labels[@]}" || { say "Cancelled. Nothing changed."; exit 0; }
  picked=()
  for i in "${CHECKLIST[@]}"; do [[ -n "${ids[i]}" ]] && picked+=("${ids[i]}"); done
  todo=("${picked[@]}")
  (( ${#todo[@]} )) || { say "Nothing picked. Nothing changed."; exit 0; }
  say ""
fi

for id in "${todo[@]}"; do
  say "${B}$("$(fn label "$id")")${R}  ${D}$id · $("$(fn title "$id")")${R}"
  (( details )) && say "      ${D}$("$(fn detail "$id")")${R}"
  "$(fn install "$id")"
done

say ""
if dry; then
  say "Dry run, nothing changed. Add --details to see the diffs."
  exit 0
fi

# Summary: what this run did, in a box; the footer says what's next.
summary=""
for id in "${todo[@]}"; do
  component_state "$id"
  case "$STATE" in
    installed) mark="${G}✓${R}" what="ready" ;;
    partial)   mark="${Y}◐${R}" what="partly done · ./install.sh $id finishes it" ;;
    *)         mark="${D}○${R}" what="skipped · ./install.sh $id any time" ;;
  esac
  summary+="$mark $("$(fn label "$id")")"$'\x1f'"$D$what$R"$'\n'
done
printf '%s' "$summary" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"
if [[ -t 1 ]]; then
  printf '%s' "$summary" | print_table 3 |
    ui_box "done" "open a new terminal to pick it up" 0 "$(ui_hint "undo: ./uninstall.sh · log: ${log_file/#$HOME/\~}")"
else
  printf '%s' "$summary" | print_table 3
fi
