# The installer's tab view (./install.sh with no components named, fzf 0.63+): one tab
# per group, then a summary tab. space ticks, ←→ or tab change tabs, enter goes to the
# summary and, there, sets up what's ticked; esc leaves with nothing changed.
# install.sh sources it for tabs_pick; fzf's key callbacks run it as a script
# (bash lib/tabs.sh <what> <state dir> ...), which loads only lib/ui.sh and lib/inplace.sh.
#
# The state dir:
#   tabs     the groups, one per line, in order (the summary tab comes after them)
#   about    "group\x1eone line on what it is"
#   info     one line per component: id group tickable state badge label title detail note (\x1e between)
#   on       the ticked ids     cur  the open tab (0 = first)
#   dry/<id> its --dry-run lines (written in the background)
#   go       made when enter on the summary applies
# plus lib/inplace.sh's files (the overlap question asks in the list's header).

# tabs_pick: shows wanted (all) with todo tickable; sets todo to the ticked ones.
# 1 = cancelled. Needs install.sh's wanted, todo, ST/NT (state and note per id).
tabs_pick() {
  local T id g bg rc=0 on
  local -a picked=()
  T=$(mktemp -d) || return 1
  mkdir "$T/dry"; : >"$T/tabs"; : >"$T/about"; : >"$T/info"; : >"$T/on"; echo 0 >"$T/cur"
  for id in "${wanted[@]}"; do
    g=$(group_of "$id")
    grep -qxF "$g" "$T/tabs" || { echo "$g" >>"$T/tabs"; printf '%s\x1e%s\n' "$g" "${GROUP_ABOUT[$g]:-}" >>"$T/about"; }
    on=0; [[ " ${todo[*]} " == *" $id "* ]] && on=1
    (( on )) && on_by_default "$id" && echo "$id" >>"$T/on"
    printf '%s\x1e' "$id" "$g" "$on" "${ST[$id]}" "$(badge "${ST[$id]}")" "$("$(fn label "$id")")" \
      "$("$(fn title "$id")")" "$("$(fn detail "$id")")" >>"$T/info"
    printf '%s\n' "${NT[$id]}" >>"$T/info"
  done
  # what --dry-run would print for each, for the summary's footer (questions not asked)
  ( log_file=/dev/null mode=dry
    for id in "${todo[@]}"; do
      "$(fn install "$id")" </dev/null 2>&1 | grep -v -- '– skipped' >"$T/dry/$id.part"; mv "$T/dry/$id.part" "$T/dry/$id"
    done ) >/dev/null 2>&1 &
  bg=$!
  local cb="bash '$repo/lib/tabs.sh'" k
  local -a binds=()
  for k in right:1 tab:1 left:-1 btab:-1; do binds+=(--bind="${k%%:*}:transform:$cb go '$T' ${k#*:}"); done
  for k in y n esc; do binds+=(--bind="$k:transform:$cb key '$T' $k {2}"); done
  bash "$repo/lib/tabs.sh" rows "$T" |
    ui_fzf "work toolkit · set up" --no-input --header-lines=1 --delimiter=$'\t' --with-nth=1 \
      --footer=' ' --with-shell='bash -c' "${binds[@]}" \
      --bind="start:unbind(y,n)+transform:$cb header '$T'" \
      --bind="focus:transform:$cb foot '$T' {2}" \
      --bind="space:transform:$cb tick '$T' {2} {n}" \
      --bind="enter:transform:$cb key '$T' enter {2}" \
      --bind="resize:transform:$cb go '$T' 0" >/dev/null || rc=$?
  kill "$bg" 2>/dev/null
  if [[ -e $T/go ]]; then
    for id in "${wanted[@]}"; do grep -qxF "$id" "$T/on" && picked+=("$id"); done
    todo=("${picked[@]}")
  else rc=1; fi
  rm -rf "$T"
  return "$rc"
}

# ------------------------------------------------------------ callbacks ---
# One component from info: sets I_ID I_GROUP I_TICK I_STATE I_BADGE I_LABEL I_TITLE I_DETAIL I_NOTE.
t_info() {
  local line; line=$(grep -m1 "^$1"$'\x1e' "$T/info") || return 1
  IFS=$'\x1e' read -r I_ID I_GROUP I_TICK I_STATE I_BADGE I_LABEL I_TITLE I_DETAIL I_NOTE <<<"$line"
}
t_on() { grep -qxF "$1" "$T/on"; }
t_load() { mapfile -t TABS <"$T/tabs"; read -r CUR <"$T/cur"; NT=${#TABS[@]}; }   # summary = tab NT

# The open tab's rows, laid out: title row first, the id hidden after a TAB.
t_rows() {
  local mark n=0
  {
    if (( CUR < NT )); then
      printf '\x1f%s\x1f%s\x1f%s\t\n' "${C_BOLD}COMPONENT$C_RESET" "${C_BOLD}STATE$C_RESET" "${C_BOLD}WHAT YOU GET$C_RESET"
      while IFS=$'\x1e' read -r I_ID I_GROUP I_TICK I_STATE I_BADGE I_LABEL I_TITLE I_DETAIL I_NOTE; do
        [[ $I_GROUP == "${TABS[CUR]}" ]] || continue
        if (( ! I_TICK )); then mark="   "; elif t_on "$I_ID"; then mark="$C_GREEN[✓]$C_RESET"; else mark="[ ]"; fi
        printf '%s\x1f%s\x1f%s\x1f%s\t%s\n' "$mark" "$I_ID" "$I_BADGE" "$C_DIM$I_TITLE$C_RESET" "$I_ID"
      done <"$T/info"
    else
      printf '%s\x1f%s\t\n' "${C_BOLD}SETS UP$C_RESET" "${C_BOLD}WHAT YOU GET$C_RESET"
      while IFS=$'\x1e' read -r I_ID I_GROUP I_TICK I_STATE I_BADGE I_LABEL I_TITLE I_DETAIL I_NOTE; do
        t_on "$I_ID" || continue
        printf '%s\x1f%s\t%s\n' "$C_GREEN✓$C_RESET $I_ID" "$C_DIM$I_TITLE$C_RESET" "$I_ID"; n=$((n + 1))
      done <"$T/info"
      (( n )) || printf '%s\x1f\t\n' "${C_DIM}Nothing ticked: ← to go back and tick, esc to leave$C_RESET"
    fi
  } | print_table 3 "$(ui_pick_width)"
}

# The header: the tab strip (on more rows when the window is narrow), what the open tab
# is, then the keys.
t_strip() {
  local -a labels=("${TABS[@]}") row=()
  local w=$(( ${FZF_COLUMNS:-$(ui_cols)} - 6 )) used=1 i first=0 l out=""
  labels+=("Summary $(grep -c '' "$T/on")")
  for i in "${!labels[@]}"; do
    l=${#labels[i]}
    if (( ${#row[@]} && used + l + 3 > w )); then
      out+="$(ui_tabs $(( CUR - first )) "${row[@]}")"$'\n'; row=() used=1 first=$i
    fi
    row+=("${labels[i]}"); (( used += l + 3 ))
  done
  printf '%s' "$out$(ui_tabs $(( CUR - first )) "${row[@]}")"
}
t_header() {
  local about keys
  if (( CUR < NT )); then
    about=$(grep -m1 "^${TABS[CUR]}"$'\x1e' "$T/about"); about=${about#*$'\x1e'}
    keys="←→: tab · space: tick · enter: to the summary · esc: cancel"
  else
    about="What enter sets up. Each change still asks first (Enter = yes); ./uninstall.sh undoes any of it."
    keys="←→: tab · enter: set these up · esc: cancel"
  fi
  [[ -n $about ]] && about=$(fold -s -w $(( ${FZF_COLUMNS:-$(ui_cols)} - 6 )) <<<"$about" | sed "s/^/$C_DIM/; s/\$/$C_RESET/")
  ui_sort_keys "$keys" "$(t_strip)${about:+$'\n'$about}"
}

# The footer for the row under the cursor: on a tab, its whole line and what it touches
# on disk; on the summary, what --dry-run prints for it.
t_foot() {
  local w=$(( ${FZF_COLUMNS:-$(ui_cols)} - 6 )) out
  [[ -n ${1:-} ]] && t_info "$1" || { printf ' '; return; }
  if (( CUR < NT )); then
    out="$I_TITLE"$'\n'"touches: $I_DETAIL"
    [[ -n $I_NOTE ]] && out+=$'\n'"$I_NOTE"
    (( I_TICK )) || [[ $I_STATE != installed ]] || out+=$'\n'"already set up: ./uninstall.sh $I_ID removes it"
    fold -s -w "$w" <<<"$out"
  elif [[ -e $T/dry/$1 ]]; then
    if [[ -s $T/dry/$1 ]]; then cat "$T/dry/$1"; else echo "nothing to ask: it is set up as it is"; fi
  else echo "working out what it would do…"; fi
}

t_reload() { ip_join "reload-sync($cb rows '$T')" "$(ui_fz change-header "$(t_header)")" "${1:-first}"; }

# go <step>: another tab (0 = the same one again, laid out for a resized window)
t_go() {
  [[ $(ip_get mode) == confirm ]] && return 0
  CUR=$(( (CUR + $1 + NT + 1) % (NT + 1) )); echo "$CUR" >"$T/cur"
  if (( $1 )); then t_reload; else t_reload "pos(${FZF_POS:-1})"; fi
}

# tick <id> <row index>: on a tab, tick or untick that row
t_tick() {
  [[ $(ip_get mode) == confirm ]] && return 0
  (( CUR < NT )) && t_info "${1:-}" && (( I_TICK )) || return 0
  if t_on "$1"; then grep -vxF "$1" "$T/on" >"$T/on.new"; mv "$T/on.new" "$T/on"; else echo "$1" >>"$T/on"; fi
  t_reload "pos($(( $2 + 1 )))"
}

# Both bars would be there afterwards (ticked, or in place already), one of them ticked.
t_overlap() {
  local id there=0 ticked=0
  for id in dash2dock dash-to-panel; do
    t_info "$id" || return 1
    if t_on "$id"; then (( there++, ticked++ )); elif [[ $I_STATE == installed || $I_STATE == partial ]]; then (( there++ )); fi
  done
  (( there == 2 && ticked ))
}

# key <key> <id>: enter, y, n, esc. In a question they answer it.
t_key() {
  local a i=0 id g
  if [[ $(ip_get mode) == confirm ]]; then
    a=$(ip_answer "$1"); [[ -n $a ]] || return 0
    if [[ $a == yes ]]; then touch "$T/go"; echo accept; return; fi
    # no: back to the tab with the dock, on its row
    t_info dash2dock
    for (( CUR = 0; CUR < NT; CUR++ )); do [[ ${TABS[CUR]} == "$I_GROUP" ]] && break; done
    echo "$CUR" >"$T/cur"
    while IFS=$'\x1e' read -r id g _; do [[ $g == "$I_GROUP" ]] || continue; (( i++ )); [[ $id == dash2dock ]] && break; done <"$T/info"
    ip_join "$(ip_back)" "$(t_reload "pos($i)")"
    return
  fi
  case $1 in
    esc) echo abort ;;
    enter)
      if (( CUR < NT )); then t_go $(( NT - CUR )); return; fi
      if t_overlap; then
        ip_confirm "Both bars use the same space. Keep both?" overlap n "$(t_strip)"; return
      fi
      touch "$T/go"; echo accept ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
  . "$repo/lib/ui.sh"; [[ -z "${NO_COLOR:-}" ]] && ui_color
  T=$2 IP=$2 cb="bash '$repo/lib/tabs.sh'"
  . "$repo/lib/inplace.sh"
  t_load
  case $1 in
    rows)   t_rows ;;
    header) ui_fz change-header "$(t_header)" ;;
    foot)   ui_fz change-footer "$(t_foot "${3:-}")" ;;
    go)     t_go "$3" ;;
    tick)   t_tick "${3:-}" "${4:-0}" ;;
    key)    t_key "$3" "${4:-}" ;;
  esac
fi
