#!/usr/bin/env bash
# Sets up the work toolkit on this machine. Safe to run any number of times:
# it checks what's already in place and only asks about what isn't.
# `./install.sh help` lists the commands. Undo any part with ./uninstall.sh.
# Log: ~/.local/state/work-toolkit/setup.log
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
    -d|--details)   details=1 ;;
    -p|--plain)     export WORK_TOOLKIT_PLAIN=1 ;;
    --layer=*)      layer=${arg#--layer=} ;;
    -*) printf '✗ unknown option %s · see: ./install.sh help\n' "$arg" >&2; exit 2 ;;
    *)  wanted+=("$arg") ;;
  esac
done

setup_phase=install   # lets lib/setup.sh keep your originals (see "originals" there)
# downloads go in ~/.local/bin: a part set up in this run is found by the ones that need it
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || PATH="$HOME/.local/bin:$PATH"
. "$repo/lib/setup.sh"
. "$repo/lib/components.sh"
. "$repo/lib/tabs.sh"

if (( help )); then
  ui_help ./install.sh "set up the work toolkit" <<'EOF'
## Commands
./install.sh	a tab per group: tick what to set up, then one question per change	Enter = yes
./install.sh <component>...	just those, e.g. ./install.sh zsh
./install.sh ls	every component and whether it's installed
./install.sh help	this page

## Options
--dry-run	show what would change; changes nothing
--details	also show diffs (e.g. ~/.bashrc) before asking
--yes	no questions, for scripted setups
--plain	don't use or offer gum (the nicer-looking lists)
--layer=<name>	only that layer's parts (tk layer add and fk install use it)

./install.sh ls names every component; ./uninstall.sh undoes any of them.
Log: ~/.local/state/work-toolkit/setup.log
EOF
  exit 0
fi

# What this run may touch: one layer's parts (--layer), else everything but standalone layers' (fk install)
if [[ -n $layer ]]; then
  layer_path "$repo" "$layer" >/dev/null || { printf '✗ no layer %s · see: tk layer ls\n' "'$layer'" >&2; exit 2; }
  mapfile -t allowed < <(layer_parts "$layer")
else mapfile -t allowed < <(main_parts); fi
for w in "${wanted[@]}"; do
  [[ " ${allowed[*]} " == *" $w "* ]] && continue
  if [[ " ${COMPONENTS[*]} " == *" $w "* ]]; then printf '✗ %s is set up with: %s %s\n' "'$w'" "$(setup_cmd "$w")" "$w" >&2
  else printf '✗ unknown command or component %s · see: ./install.sh ls\n' "'$w'" >&2; fi
  exit 2
done
named=${#wanted[@]}
(( named )) || wanted=("${allowed[@]}")
[[ -n $layer ]] && (( ! ${#wanted[@]} )) && { echo "The $layer layer has nothing to set up."; exit 0; }
# how to set a part up again, and undo it: ./install.sh, or a standalone layer's own command
again=./install.sh undo=./uninstall.sh
[[ -n $layer && -n ${STANDALONE[$layer]:-} ]] && again="${STANDALONE[$layer]} install" undo="${STANDALONE[$layer]} uninstall"

if [[ "$mode" == ask && $list == 0 && ! -t 0 ]]; then
  echo "This installer asks before each change, but there's no terminal to ask in."
  echo "Run it in a terminal, or use --dry-run to preview / --yes to accept everything. (./install.sh ls just lists.)"
  exit 1
fi

badge() {   # badge <state> [what it needs] [note]
  case "$1" in
    installed) printf '%s✓ installed%s' "$G" "$R" ;;
    partial)   printf '%s◐ partly%s' "$Y" "$R" ;;
    missing)   printf '%s○ not installed%s' "$Y" "$R" ;;
    needs)     printf '%s○ needs %s%s' "$Y" "${2// /, }" "$R" ;;
    unsupported) printf '%s⊘ not supported here%s' "$D" "$R" ;;
    *) if [[ ${3:-} == "needs "* ]]; then printf '%s– %s%s' "$D" "${3%%,*}" "$R"; else printf '%s– n/a%s' "$D" "$R"; fi ;;
  esac
}

logf ""; logf "=== install $ts ($mode) ${wanted[*]}"
# Overview: every component and its state, grouped, in one box.
todo=() prev="" table=""
if (( list )); then table+="${B}COMPONENT${R}"$'\x1f'"${B}KIT${R}"$'\x1f'"${B}STATE${R}"$'\x1f'"${B}NOTE${R}"$'\n'
else table+="${B}COMPONENT${R}"$'\x1f'"${B}STATE${R}"$'\x1f'"${B}NOTE${R}"$'\n'; fi
skipped=0
declare -A ST=() NT=() ND=()   # each one's state, note and the parts it needs first, for the tabs
for id in "${wanted[@]}"; do
  component_state "$id"; ST[$id]=$STATE NT[$id]=$NOTE ND[$id]=$NEED
  [[ "$STATE" == unsupported ]] && (( skipped++ ))
  if (( ! named )) && [[ "$(group_of "$id")" != "$prev" ]]; then
    [[ -n "$prev" ]] && table+=$'\n'
    prev=$(group_of "$id"); table+="${D}$prev${R}"$'\n'
  fi
  if (( list )); then table+="  $id"$'\x1f'"$D$(repo_of "$id")$R"$'\x1f'"$(badge "$STATE" "$NEED" "$NOTE")"$'\x1f'"$D${NOTE}$R"$'\n'
  else table+="  $id"$'\x1f'"$(badge "$STATE" "$NEED" "$NOTE")"$'\x1f'"$D${NOTE}$R"$'\n'; fi
  [[ "$STATE" == missing || "$STATE" == partial || "$STATE" == needs ]] && todo+=("$id")
  # named on the command line and installed already: still offer its settings menu (keep / look / defaults)
  (( named )) && [[ "$STATE" == installed && " ${LOOK_PARTS[*]} " == *" $id "* ]] && todo+=("$id")
done
# Naming only installed look components (their settings menu): no table, heading or summary, just the menu.
quick=0
if (( named )) && (( ${#todo[@]} == named )); then
  quick=1
  for id in "${todo[@]}"; do [[ " ${LOOK_PARTS[*]} " == *" $id "* ]] || quick=0; done
fi
if (( quick )); then
  ok_pad=""
  if [[ "$mode" == ask && "${WORK_TOOLKIT_PLAIN:-0}" != 1 ]]; then use_gum || true; fi
  for id in "${todo[@]}"; do "$(fn install "$id")"; done
  exit 0
fi
# A full setup in a terminal opens on the tabs (fzf 0.63+: its footer), even with everything
# set up (to look through); else the table and the checklist below.
tabs=0
[[ "$mode" == ask && $named == 0 && $list == 0 && -t 1 ]] && ui_fzf_at_least 0.63 && tabs=1
printf '%s' "$table" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"
if (( ! tabs )); then
  say ""
  if (( ${#todo[@]} )); then right="${#todo[@]} to set up"; else right="${G}all set${R}"; fi
  printf '%s' "$table" | ui_table "work toolkit" "$right"
  # Which machine this is, and what that rules out (the reasons are in the NOTE column).
  say "${D}This machine: $OS_NAME · $DESKTOP_NAME · ${PKG_MGR/none/no package manager}${R}"
  (( skipped )) && say "${D}$skipped component(s) can't run here and are skipped (⊘ above, with the reason).${R}"
  (( list )) && exit 0
  say ""
fi
if (( ${#todo[@]} == 0 && ! tabs )); then
  if (( skipped == ${#wanted[@]} )); then say "None of these can run on this machine. Nothing to do."
  else say "Everything is already set up. Nothing to do."; fi
  exit 0
fi

if (( tabs )); then
  had=${#todo[@]}
  tabs_pick || { say "Cancelled. Nothing changed."; exit 0; }
  (( had )) || { say "Everything is already set up. Nothing to do."; exit 0; }
  (( ${#todo[@]} )) || { say "Nothing picked. Nothing changed."; exit 0; }
  logf "picked: ${todo[*]}"
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

# Pick what to set up (nothing ticked: you tick what you want with tab). Named components or
# --yes / --dry-run skip the list.
if [[ "$mode" == ask && $named == 0 ]] && (( ! tabs )); then
  say "Tick what you want with ${B}tab${R}, then ${B}Enter${R} sets it up."
  say "${D}Each change still asks first (Enter = yes), and $undo undoes any of it.${R}"
  say ""
  labels=() ids=() prev=""
  for id in "${todo[@]}"; do
    if [[ "$(group_of "$id")" != "$prev" ]]; then
      prev=$(group_of "$id"); labels+=("## $prev"); ids+=("")
    fi
    labels+=("$id"$'\t'"$("$(fn title "$id")")"); ids+=("$id")
  done
  checklist "Pick what to set up:" "${labels[@]}" || { say "Cancelled. Nothing changed."; exit 0; }
  picked=()
  for i in "${CHECKLIST[@]}"; do [[ -n "${ids[i]}" ]] && picked+=("${ids[i]}"); done
  todo=("${picked[@]}")
  (( ${#todo[@]} )) || { say "Nothing picked. Nothing changed."; exit 0; }
  say ""
fi

# What a picked part needs and isn't set up yet joins the run, set up before it (setup order).
declare -A in_run=()
for id in "${todo[@]}"; do in_run[$id]=1; done
more=1
while (( more )); do
  more=0
  for id in "${!in_run[@]}"; do
    [[ -v ND[$id] ]] || { component_state "$id"; ND[$id]=$NEED; }
    for need in ${ND[$id]}; do [[ -v in_run[$need] ]] || { in_run[$need]=1; more=1; }; done
  done
done
todo=()
for id in "${COMPONENTS[@]}"; do [[ -v in_run[$id] ]] && todo+=("$id"); done

for id in "${todo[@]}"; do
  say "${B}$("$(fn label "$id")")${R}  ${D}$id · $("$(fn title "$id")")${R}"
  (( details )) && say "      ${D}$("$(fn detail "$id")")${R}"
  if [[ -n ${ND[$id]} ]]; then   # it needed other parts: set up now?
    component_state "$id"
    if [[ $STATE == needs ]]; then
      if dry; then say "      ${D}set up right after ${NEED// / and }${R}"; else skip "needs ${NEED// / and }, which isn't set up"; fi
      continue
    fi
  fi
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
    partial)   mark="${Y}◐${R}" what="partly done · $again $id finishes it" ;;
    *)         mark="${D}○${R}" what="skipped · $again $id any time" ;;
  esac
  summary+="$mark $("$(fn label "$id")")"$'\x1f'"$D$what$R"$'\n'
done
printf '%s' "$summary" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"
if [[ -t 1 ]]; then
  printf '%s' "$summary" | print_table 3 |
    ui_box "done" "open a new terminal to pick it up" 0 "$(ui_hint "undo: $undo")"
  say "${D}log: ${log_file/#$HOME/\~}${R}"
else
  printf '%s' "$summary" | print_table 3
fi
