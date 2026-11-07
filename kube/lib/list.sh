# kx lists: one fzf that stays open while you work in it. Sourced by kube/bin/kx
# after resources.sh (uses its helpers). Needs fzf 0.63+ (footer, transforms).
#
# How it works:
#   - every key that does something runs `kx __list <state> key ...`, which
#     prints fzf actions: a question in the header, a status in the footer,
#     a refresh of the rows... The list itself never closes.
#   - questions: yes/no ones bind y and n for the moment; typed ones (a port,
#     a count, a name on prod) use the prompt, filled in where it can be.
#   - slow work (kubectl delete, rollout, port lookups) runs in the background
#     and posts fzf actions into <state>/todo.*, which the list picks up every
#     second (every(1)), so the status line updates and the rows refresh.
#   - logs, a shell and the editor need the whole terminal: fzf hands it over
#     (execute) and comes back to the same row, same filter.
#   - ctrl-e (change mode) reopens the list in amber from the rows it has, so
#     that's instant too.

LIST_FZF_MIN=0.63

list_fzf_ok() {
  local v; v=$(fzf --version 2>/dev/null | awk '{print $1}')
  [[ -n "$v" && "$(printf '%s\n%s\n' "$LIST_FZF_MIN" "$v" | sort -V | head -1)" == "$LIST_FZF_MIN" ]]
}

# ------------------------------------------------------------------ state ---
# conf: fixed for the list (kind, namespace...). vars: what changes as you go.

# Plain name=value lines (declare -p would make them local to list_load).
list_dump() { local v; for v in "$@"; do printf '%s=%q\n' "$v" "${!v}"; done; }
# A background job's changes wait in vars.after until the list shows them
# (list_todo moves them in first), so a key pressed meanwhile still sees the
# state that's on screen.
list_save() {   # writes vars
  local to="$S/vars"; [[ -n "${LIST_JOB:-}" ]] && to="$S/vars.after"
  list_dump all changes can_edit can_delete mode pending saved_q >"$to.new" 2>/dev/null &&
    mv "$to.new" "$to"
}
list_load() { . "$S/conf"; . "$S/vars"; }

# Queue fzf actions for the list (from a background job).
list_todo() {   # actions
  local f="$S/todo.$(date +%s%N)" a="$1"
  if [[ -e "$S/vars.after" ]]; then
    a="$(fz execute-silent "mv -f $(printf %q "$S/vars.after") $(printf %q "$S/vars")")${a:++$a}"
  fi
  printf '%s' "$a" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null
}

# The status line. Progress stays put; a result (toast) clears itself after
# 5 seconds, unless something newer is showing by then.
# The message's id is recorded when the list shows it, not when it's made.
list_footer() {   # text [toast]
  local id f; id=$(date +%s%N); f=$(printf %q "$S/footer")
  if [[ "${2:-}" == toast ]]; then
    ( sleep 5; [[ "$(cat "$S/footer" 2>/dev/null)" == "$id" ]] && list_todo "change-footer( )" ) \
      </dev/null >/dev/null 2>&1 &
  fi
  fzj "$(fz execute-silent "echo $id >$f")" "$(fz change-footer "$1")"
}

# fzf action with a text argument, wrapped in brackets the text doesn't contain.
fz() {   # action text
  local p
  for p in '()' '[]' '{}' '<>' '~~' '!!' '@@' '##' '%%' '^^' '&&' '**' ';;' '//' '||'; do
    [[ "$2" == *"${p:1:1}"* ]] && continue
    printf '%s%s%s%s' "$1" "${p:0:1}" "$2" "${p:1:1}"; return
  done
}
# Join actions with +.
fzj() { local IFS=+; printf '%s' "$*"; }

list_cb_cmd() { printf '%q __list %q' "$SELF" "$S"; }   # how fzf calls back

# ----------------------------------------------------------------- texts ---

list_where() {
  local w
  if (( all )); then w="every namespace"; else w="namespace $ns"; fi
  if [[ -n "$of" ]]; then w+=" · pods of $of"; elif [[ -n "$selector" ]]; then w+=" · $selector"; fi
  (( changes )) && w+=" · CHANGES ON"
  printf '%s' "kx · $kind · $(current_ctx) · $w"
}

list_prompt() { if (( changes )); then printf '%s' "$kind (changes)> "; else printf '%s' "$kind> "; fi; }

# The usual hint lines (raw "key: what · ..." text; ui_keys styles it).
list_hints() {
  local h="" mark="!"
  if (( changes )); then
    is_prod "$(current_ctx)" && mark="!!"
    h="${mark}CHANGES ON"
    (( can_edit )) && h+=" · ctrl-o: edit"
    (( can_delete )) && h+=" · ctrl-x: delete"
    (( can_edit && scale )) && h+=" · ctrl-s: scale"
    h+=$'\n'
  fi
  h+="$header"$'\n'
  h+="ctrl-p: $pane_word pane · "
  if (( all )); then h+="ctrl-a: just namespace $ns · "; else h+="ctrl-a: every namespace · "; fi
  h+="ctrl-d: default namespace · "
  if (( changes )); then h+="ctrl-e: changes off · "; else h+="ctrl-e: changes · "; fi
  h+="alt-s: sort · alt-←→: column · alt-shift-←→: move it · esc: quit"
  printf '%s' "$h"
}
list_max() { echo $(( $(ui_cols) * 45 / 100 - 8 )); }
list_header() { ui_sort_keys "$(list_hints)" "" "$(list_max)"; }   # the column titles stay under it

# A question in the header: amber, folded, then its keys.
list_question_header() {   # question keys [warning-lines]
  local q out=""
  is_prod "$(current_ctx)" && out+="$(ui_badge PROD) ${C_RED}$(current_ctx)${C_RESET}"$'\n'
  [[ -n "${3:-}" ]] && out+="$3"$'\n'
  q=$(fold -s -w $(( $(ui_cols) - 12 )) <<<"$1" | sed "s/^/${C_YELLOW}${C_BOLD}/; s/\$/${C_RESET}/")
  out+="$q"
  ui_sort_keys "$2" "$out" "$(list_max)"   # the column titles stay under it; a resize wraps the keys again
}

# Back to the plain list: header, prompt, y/n keys, filter.
list_restore() {   # [footer text] [toast]
  local -a a=()
  mode=list pending=""
  # the filter you had comes back (a typed answer may have replaced it)
  a+=("$(fz change-header "$(list_header)")" "$(fz change-prompt "$(list_prompt)")" "unbind(y,n)"
      "$(fz change-query "$saved_q")" enable-search)
  [[ -n "${1:-}" ]] && a+=("$(list_footer "$1" "${2:-}")")
  list_save
  fzj "${a[@]}"
}

# Ask yes / no. pending is what runs on yes.
list_confirm() {   # question pending [default y|n] [warning-lines]
  local d="${3:-n}" keys
  mode=confirm pending="$2"; list_save
  if [[ "$d" == y ]]; then keys="y: yes (enter too) · n: no (esc too)"; else keys="y: yes · n: no (enter, esc too)"; fi
  [[ "$d" == y ]] && pending="default-yes $pending" && list_save
  fzj "$(fz change-header "$(list_question_header "$1" "$keys" "${4:-}")")" \
      "$(fz change-prompt "${C_YELLOW}y / n? ${C_RESET}")" "rebind(y,n)" "$(list_footer " ")" \
      "$(fz change-query "$saved_q")" enable-search
}

# Ask for typed text on the prompt line. pending gets the answer appended.
list_ask() {   # question pending prefill prompt [warning-lines]
  mode=ask pending="$2"; list_save
  fzj "$(fz change-header "$(list_question_header "$1" "enter: ok · esc: cancel" "${5:-}")")" \
      "$(fz change-prompt "${C_YELLOW}${4:-> }${C_RESET}")" disable-search "$(fz change-query "$3")" \
      "$(list_footer " ")"
}

# ------------------------------------------------------------------- rows ---

list_rows() {   # prints the rows (header line first); keeps a copy for relaunches
  local out rc
  out=$(RES_SELECTOR="$selector" res_rows "$kind" "$all" "$ns"); rc=$?
  if (( rc == 2 )); then out=$'\t\t'"  (no $kind here)"; fi
  (( rc == 1 )) && out=$'\t\t'"  (couldn't list $kind: see kx doctor)"
  printf '%s\n' "$out" | tee "$S/rows.new" | ui_sort_feed && mv "$S/rows.new" "$S/rows"   # in the column sort
}
# Always the LAST action in a chain: with --track --id-nth, fzf drops actions after a reload.
list_reload() { printf 'reload(%s rows)' "$(list_cb_cmd)"; }

# Where a row is in the list as fzf shows it for this filter (1 = top).
list_pos() {   # ns name query
  local n
  n=$(tail -n +2 "$S/rows" 2>/dev/null | fzf --filter="$3" --delimiter=$'\t' --with-nth=3 2>/dev/null |
      awk -F'\t' -v a="$1" -v b="$2" '$1 == a && $2 == b { print NR; exit }')
  echo "${n:-1}"
}

# ------------------------------------------------------------- the list ---

# Usage: browse <kind> [-A|--all] [-n|--namespace <ns>] [filter]
# kind_setup must have run for <kind> (PK_ACT says what the keys do).
browse() {
  local S rc
  S=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/kx-list.XXXXXX") || return 1
  list_main "$@"; rc=$?
  rm -rf "$S"
  return $rc
}

list_main() {
  local kind="$1" query=""
  local all=0 changes=0 can_edit=0 can_delete=0 mode=list pending="" saved_q=""
  local ns="${RES_NS:-}" selector="${RES_SELECTOR:-}" of="${RES_OF:-}"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -A|--all) all=1 ;;
      -n|--namespace) [[ $# -ge 2 ]] || die "Usage: -n <namespace>"; ns="$2"; shift ;;
      -*) die "Unknown option '$1' · kx help" ;;
      *) query="$1" ;;
    esac
    shift
  done
  need_ctx
  [[ -n "$ns" ]] || ns=$(cur_ns)
  local header="$PK_HEADER" pane="$PK_PANE" act="$PK_ACT" scale="$PK_SCALE" wkind="${WORKLOAD_KIND:-deployments}"
  local pane_word=details
  case "$kind" in secrets) pane_word=values ;; configmaps) pane_word=settings ;; esac

  local rows rc
  rows=$(RES_SELECTOR="$selector" res_rows "$kind" "$all" "$ns"); rc=$?
  if (( rc == 2 )); then
    if (( all )); then info "No $kind in any namespace on $(current_ctx)."; return 0; fi
    info "${C_DIM}No $kind in namespace $ns · showing every namespace${C_RESET}"
    all=1; rows=$(RES_SELECTOR="$selector" res_rows "$kind" 1 "$ns"); rc=$?
    (( rc == 2 )) && { info "No $kind in any namespace on $(current_ctx)."; return 0; }
  fi
  (( rc == 0 )) || return 1

  if ! interactive; then   # piped / no fzf: an exact name still works, else print the list
    local line sel_ns name
    line=$(awk -F'\t' -v q="$query" 'NR > 1 && $2 == q { print $1 "\t" $2; exit }' <<<"$rows")
    if [[ -n "$query" && -n "$line" ]]; then
      IFS=$'\t' read -r sel_ns name <<<"$line"
      case "$act" in
        values|generic) res_pane "$pane" "$kind" "$sel_ns" "$name" ;;
        *) list_run_enter "$act" "$sel_ns" "$name" ;;
      esac
      return 0
    fi
    cut -f3- <<<"$rows" | print_table 3 | sed 's/\x1b\[[0-9;]*m//g'; return 0
  fi
  list_fzf_ok || die "kx lists need fzf $LIST_FZF_MIN or newer (you have $(fzf --version | awk '{print $1}')). Install it with: tk install fzf"

  list_dump kind ns selector of header pane act scale wkind pane_word >"$S/conf"
  list_save
  printf '%s\n' "$rows" >"$S/rows"

  # A filter that matches one row runs it straight away (kx pods api -> its logs).
  if [[ -n "$query" && "$act" != values && "$act" != generic ]]; then
    local hits; hits=$(tail -n +2 "$S/rows" | fzf --filter="$query" --delimiter=$'\t' --with-nth=3 2>/dev/null)
    if [[ $(grep -c . <<<"$hits") -eq 1 ]]; then
      local h_ns h_name; IFS=$'\t' read -r h_ns h_name _ <<<"$hits"
      list_run_enter "$act" "$h_ns" "$h_name"
      [[ "$act" == single-* ]] && return 0
    fi
  fi

  local cb out marker pos=1 last_ns="" last_name=""
  cb=$(list_cb_cmd)
  while :; do
    local -a look=()
    if (( changes )); then
      local col=yellow; is_prod "$(current_ctx)" && col=red
      look=(--color="border:$col,label:$col,prompt:$col")
    fi
    pos=1; [[ -n "$last_name" ]] && pos=$(list_pos "$last_ns" "$last_name" "$query")
    local -a binds=(
      --bind "start:unbind(y,n)"
      --bind "load:pos($pos)+unbind(load)"
      --bind "every(0.3):transform:f=\$(ls $(printf %q "$S")/todo.* 2>/dev/null | head -1); [ -n \"\$f\" ] && cat \"\$f\" && rm -f \"\$f\""
      # the key hints re-wrap for the room the pane leaves (fzf has moved it by then)
      --bind 'ctrl-p:change-preview-window(right,55%,nohidden|down,60%,nohidden|hidden)+transform:. "$UI_SORT_LIB"; ui_sort_step pane'
    )
    local k
    for k in enter esc y n ctrl-r ctrl-f ctrl-s ctrl-l ctrl-a ctrl-d ctrl-e ctrl-o ctrl-x; do
      binds+=(--bind "$k:transform:$cb key $k {1} {2} {q}")
    done
    out=$(ui_fzf "$(list_where)" "${look[@]}" \
        --with-shell='bash -c' --delimiter=$'\t' --with-nth=3 --header-lines=1 \
        --sortable --track --id-nth=1,2 --print-query --query="$query" --prompt="$(list_prompt)" \
        --header="$(list_hints)" --footer=' ' \
        --preview="$(printf %q "$SELF") __pane $pane $(printf %q "$kind") {1} {2}" \
        --preview-window='right,55%,hidden,wrap' --preview-label=' shift ↑/↓ scrolls ' \
        "${binds[@]}" <"$S/rows")
    rc=$?
    list_load
    query=$(sed -n 1p <<<"$out")
    marker=$(grep -m1 '^@kx:' <<<"$out")
    local line; line=$(tail -n 1 <<<"$out")
    IFS=$'\t' read -r last_ns last_name _ <<<"$line"
    case "$marker" in
      @kx:relaunch) continue ;;                       # change mode on / off: reopen in its colours
      @kx:run) list_run_enter "$act" "$last_ns" "$last_name"; return 0 ;;   # kx logs / shell / why / restart
      *) return 0 ;;                                  # esc
    esac
  done
}

# What enter does for the one-shot lists (kx logs, kx shell...), and for a
# filter that matched one row.
list_run_enter() {   # act ns name
  case "$1" in
    pods|single-logs) pod_logs "$2" "$3" ;;
    single-shell)     pod_shell "$2" "$3" ;;
    single-why)       why_report "$2" "$3" ;;
    single-restart)   workload_restart_fg "$2" deployment "$3" ;;
    workloads)        list_pods_of "$2" "${WORKLOAD_KIND:-deployments}" "$3" ;;
    services)         do_forward "$2" "service/$3" ;;
  esac
}

list_pods_of() {   # ns kind name: the list of a workload's pods
  local sel
  sel=$(workload_selector "$1" "$2/$3") || { warn "Can't tell which pods belong to $3."; return 0; }
  kind_setup pods
  RES_SELECTOR="$sel" RES_NS="$1" RES_OF="$3" browse pods
}

# -------------------------------------------------------------- callbacks ---

# kx __list <state> rows | key <key> <ns> <name> <query> | full <what> ... | job <what> ...
list_cb() {
  S="$1"; local ev="$2"; shift 2
  local kind ns selector of header pane act scale wkind pane_word all changes can_edit can_delete mode pending saved_q
  list_load
  case "$ev" in
    rows) list_rows ;;
    key)  list_key "$@" ;;
    full) list_full "$@" ;;
    job)  list_job "$@" ;;
  esac
}

# Start a background job; it reports through list_todo.
list_spawn() {   # job args...
  ( "$SELF" __list "$S" job "$@" </dev/null >/dev/null 2>&1 & ) 2>/dev/null
}
# Hand the terminal to a full-screen command, then come back.
list_exec() {   # what args... -> an execute(...) action
  local c; c="$(list_cb_cmd) full$(printf ' %q' "$@")"
  fz execute "$c"
}

list_key() {   # key ns name query
  local key="$1" rns="$2" name="$3" q="$4"
  case "$mode" in
    confirm)
      case "$key" in
        y) list_yes ;;
        enter) if [[ "$pending" == default-yes* ]]; then list_yes; else list_restore "${C_DIM}Nothing done.${C_RESET}" toast; fi ;;
        n|esc) list_restore "${C_DIM}Nothing done.${C_RESET}" toast ;;
      esac
      return ;;
    ask)
      case "$key" in
        enter) list_answer "$q" ;;
        esc) list_restore "${C_DIM}Nothing done.${C_RESET}" toast ;;
      esac
      return ;;
    busy)   # looking something up before a question
      [[ "$key" == esc ]] && { mode=list; list_save; list_restore "${C_DIM}Cancelled.${C_RESET}" toast; }
      return ;;
  esac

  # Plain list mode.
  case "$key" in
    esc) echo abort; return ;;
    ctrl-a) all=$(( !all )); list_save
            fzj "$(fz change-border-label " $(list_where) ")" "$(fz change-header "$(list_header)")" "$(list_reload)"; return ;;
    ctrl-e) list_toggle_changes "$rns" "$name"; return ;;
    ctrl-d) if [[ -z "$rns" ]]; then list_footer "${C_YELLOW}This row isn't in a namespace.${C_RESET}" toast
            elif set_default_ns "$(current_ctx)" "$rns"; then
              list_footer "${C_GREEN}✓${C_RESET} Default namespace on $(current_ctx) is now $rns · new terminals use it" toast
            else list_footer "${C_RED}✗ Couldn't set the default namespace.${C_RESET}" toast; fi
            return ;;
  esac
  [[ -n "$name" ]] || return 0   # empty list: nothing to act on
  saved_q=$q

  if (( changes )); then
    case "$key" in
      ctrl-o) (( can_edit )) && fzj "$(list_exec edit "$rns" "$kind" "$name")" "$(list_reload)"; return ;;
      ctrl-x) (( can_delete )) && list_lookup delete "$rns" "$name"; return ;;
      ctrl-s) if (( can_edit && scale )); then list_lookup scale "$rns" "$name"; return; fi ;;
    esac
  fi

  case "$act:$key" in
    pods:enter)    list_logs "$rns" "$name" ;;
    pods:ctrl-s)   if is_prod "$(current_ctx)"; then
                     list_confirm "Open a shell inside $name? On prod it can change the running app." "shell $rns $name"
                   else list_shell "$rns" "$name"; fi ;;
    pods:ctrl-f)   list_lookup forward "$rns" "pod/$name" ;;
    pods:ctrl-r)   list_confirm "Restart $name? A fresh pod replaces it." "restart-pod $rns $name" ;;
    workloads:enter)  list_exec podsof "$rns" "$wkind" "$name" ;;
    workloads:ctrl-l) list_exec wlogs "$rns" "$wkind/$name" ;;
    workloads:ctrl-r) list_confirm "Restart $name? Its pods are replaced one at a time, so it stays up." "restart-workload $rns $wkind $name" ;;
    services:enter)   list_lookup forward "$rns" "service/$name" ;;
    values:enter|values:ctrl-r|generic:enter) echo toggle-preview ;;
    single-restart:enter) list_confirm "Restart $name? Its pods are replaced one at a time, so it stays up." "run" ;;
    single-*:enter) echo "print(@kx:run)+accept" ;;
  esac
}

# y on a yes/no question.
list_yes() {
  local p="${pending#default-yes }" w
  read -r -a w <<<"$p"
  case "${w[0]}" in
    run)  mode=list; list_save; echo "print(@kx:run)+accept" ;;
    shell) list_shell "${w[1]}" "${w[2]}" ;;
    restart-pod)
      list_spawn restart-pod "${w[1]}" "${w[2]}"
      list_restore "${C_YELLOW}Restarting ${w[2]}…${C_RESET}" ;;
    restart-workload)
      list_spawn restart-workload "${w[1]}" "${w[2]}" "${w[3]}"
      list_restore "${C_YELLOW}Restarting ${w[3]}…${C_RESET}" ;;
    delete)
      list_spawn delete "${w[1]}" "${w[2]}"
      list_restore "${C_YELLOW}Deleting $kind/${w[2]}…${C_RESET}" ;;
    scale)
      list_spawn scale "${w[1]}" "${w[2]}" "${w[3]}" "${w[4]}"
      list_restore "${C_YELLOW}Scaling ${w[2]} to ${w[4]} pods…${C_RESET}" ;;
    *) list_restore ;;
  esac
}

# enter on a typed question.
list_answer() {   # typed text
  local a w; a=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$1")
  read -r -a w <<<"$pending"
  case "${w[0]}" in
    forward)   # forward ns ref ports-csv
      local ports="${w[3]:-}" l r on="" x
      [[ -n "$ports" ]] && on=" It listens on ${ports//,/, }."
      x=${ports%%,*}; x=${x:-8080}
      if [[ "$a" =~ ^([0-9]{1,5}):([0-9]{1,5})$ ]]; then l=$((10#${BASH_REMATCH[1]})) r=$((10#${BASH_REMATCH[2]}))
      elif [[ "$a" =~ ^[0-9]{1,5}$ ]]; then r=$((10#$a)) l=1
      elif [[ "$a" =~ ^[0-9:]+$ ]]; then l=0 r=0
      else
        list_reask "'$a' isn't a port. Ports are numbers from 1 to 65535.$on"; return
      fi
      if (( l < 1 || l > 65535 || r < 1 || r > 65535 )); then
        list_reask "$a is out of range: ports go from 1 to 65535.$on"; return
      fi
      if [[ "$a" != *:* ]]; then
        if [[ -n "$ports" && ",$ports," != *",$r,"* ]]; then
          list_reask "It doesn't listen on $r.$on To use another local port, type local:port like 3000:$x."; return
        fi
        l=$(local_for "$r")
      fi
      if port_busy "$l"; then
        local near; near=$(free_port "$l")
        list_reask "localhost:$l is in use. Nearest free: $near (type $near:$r)."; return
      fi
      if [[ -n "${KITTY_WINDOW_ID:-}" && -n "${KITTY_LISTEN_ON:-}" ]]; then
        list_spawn forward "${w[1]}" "${w[2]}" "$l" "$r"
        list_restore "${C_YELLOW}Opening localhost:$l → ${w[2]#*/} port $r in a new tab…${C_RESET}"
      else
        fzj "$(list_restore)" "$(list_exec forward "${w[1]}" "${w[2]}" "$l" "$r")"
      fi ;;
    scale)     # scale ns name now
      [[ "$a" =~ ^[0-9]+$ ]] || { list_reask "'$a' isn't a number of pods. Type one like ${w[3]:-1}, or 0 to stop it."; return; }
      if [[ "$a" == "${w[3]}" ]]; then list_restore "${C_DIM}${w[2]} already has $a pods; nothing changed.${C_RESET}" toast; return; fi
      list_change_confirm "Scale ${w[2]} from ${w[3]:-?} to $a pods?" "scale ${w[1]} ${w[2]} ${w[3]:-?} $a" "${w[2]}" ;;
    typed-name)   # typed-name <name> <pending...> (prod)
      if [[ "$a" == "${w[1]}" ]]; then pending="${w[*]:2}"; list_yes
      else list_restore "${C_DIM}That's not ${w[1]}, so nothing changed.${C_RESET}" toast; fi ;;
    *) list_restore ;;
  esac
}

# A shell inside a pod: its own kitty tab when it can, else full screen here.
# Logs open in their own kitty tab (like a shell); without kitty, full screen here.
list_logs() {   # ns pod
  if [[ -n "${KITTY_WINDOW_ID:-}" && -n "${KITTY_LISTEN_ON:-}" ]]; then
    list_spawn logs "$1" "$2"
    list_restore "${C_YELLOW}Opening the logs of $2 in a new tab…${C_RESET}"
  else
    fzj "$(list_restore)" "$(list_exec logs "$1" "$2")"
  fi
}

list_shell() {   # ns pod
  if [[ -n "${KITTY_WINDOW_ID:-}" && -n "${KITTY_LISTEN_ON:-}" ]]; then
    list_spawn shell "$1" "$2"
    list_restore "${C_YELLOW}Opening a shell inside $2 in a new tab…${C_RESET}"
  else
    fzj "$(list_restore)" "$(list_exec shell "$1" "$2")"
  fi
}

# Ask the same typed question again, with what was wrong on top.
list_reask() {   # message
  local h; h=$(list_question_header "$(cat "$S/question" 2>/dev/null)" "enter: ok · esc: cancel" "${C_RED}✗ $1${C_RESET}")
  fz change-header "$h"
}

# Confirm a change: y/n on dev, type the name on prod.
list_change_confirm() {   # question pending name [warning-lines]
  if is_prod "$(current_ctx)"; then
    printf '%s' "$1 Type $3 to confirm." >"$S/question"
    list_ask "$1 Type $3 to confirm." "typed-name $3 $2" "" "name: " "${4:-}"
  else
    list_confirm "$1" "$2" n "${4:-}"
  fi
}

# Something to look up first (ports, current size, who owns it): say so in
# the status line, then the question appears when the lookup is done.
list_lookup() {   # what ns name|ref
  mode=busy; list_save
  local what="Looking up ${3#*/}…"
  [[ "$1" == forward ]] && what="Looking up the ports of ${3#*/}…"
  list_spawn "lookup-$1" "$2" "$3" "$saved_q"
  list_footer "${C_DIM}$what${C_RESET}"
}

list_toggle_changes() {   # ns name (the current row, to come back to it)
  if (( changes )); then changes=0; list_save; echo "print(@kx:relaunch)+accept"; return; fi
  mode=busy; list_save
  list_spawn can-i
  list_footer "${C_DIM}Checking what your access on $(current_ctx) allows…${C_RESET}"
}

# ------------------------------------------------------- full-screen bits ---

list_full() {   # what args...
  local what="$1"; shift
  case "$what" in
    logs)    pod_logs "$1" "$2" ;;
    shell)   pod_shell "$1" "$2" asked ;;
    wlogs)   workload_logs "$1" "$2" ;;
    podsof)  WORKLOAD_KIND="$2" list_pods_of "$1" "$2" "$3" ;;
    edit)    change_edit "$1" "$2" "$3"; echo; read -r -s -n1 -p "${C_DIM}Press any key to go back to the list.${C_RESET}" _ </dev/tty ;;
    forward) tput smcup 2>/dev/null; clear
             trap ':' INT; forward_screen "$1" "$2" "$3" "$4" "ctrl-c (back to the list)"; trap - INT
             tput rmcup 2>/dev/null ;;
  esac
}

# ---------------------------------------------------------- background jobs ---

list_job() {   # what args...
  local what="$1" LIST_JOB=1; shift
  case "$what" in
    lookup-forward) job_lookup_forward "$@" ;;
    lookup-scale)   job_lookup_scale "$@" ;;
    lookup-delete)  job_lookup_delete "$@" ;;
    can-i)          job_can_i ;;
    restart-pod)    job_restart_pod "$@" ;;
    restart-workload) job_restart_workload "$@" ;;
    delete)         job_delete "$@" ;;
    scale)          job_scale "$@" ;;
    forward)        job_forward "$@" ;;
    shell)          job_shell "$@" ;;
    logs)           job_logs "$@" ;;
  esac
}

job_lookup_forward() {   # ns ref query
  local ns="$1" ref="$2" path rows ports="" shown="" first n nm pre q
  unset first_name; local first_name
  saved_q=$3
  case "$ref" in
    service/*) path='{range .spec.ports[*]}{.port}{"\t"}{.name}{"\n"}{end}' ;;
    *)         path='{range .spec.containers[*]}{range .ports[*]}{.containerPort}{"\t"}{.name}{"\n"}{end}{end}' ;;
  esac
  rows=$(kubectl get "$ref" -n "$ns" -o jsonpath="$path" 2>/dev/null | awk -F'\t' 'NF && !seen[$1]++')
  while IFS=$'\t' read -r n nm; do
    [[ -n "$n" ]] || continue
    ports+="${ports:+,}$n"; shown+="${shown:+ · }$n${nm:+ $nm}"; first_name=${first_name-$nm}
  done <<<"$rows"
  if [[ -n "$ports" ]]; then
    first=${ports%%,*}
    local want_l taken=""; want_l=$(local_for "$first")
    pre=$(free_port "$want_l")
    [[ "$pre" == "$want_l" ]] || taken=" localhost:$want_l is in use, so $pre is filled in."
    [[ "$pre" == "$first" ]] || pre="$pre:$first"
    if [[ "$ports" == *,* ]]; then
      q="Forward which port of ${ref#*/}? It listens on: $shown. Enter forwards localhost:${pre%%:*} → ${first}; type another of its ports, or local:port like 3000:$first.$taken $PORT_RANGE_TXT"
    else
      q="Forward ${ref#*/} port $first${first_name:+ ($first_name)} to localhost:${pre%%:*}? Enter to go, or type another local port like 3000:$first.$taken $PORT_RANGE_TXT"
    fi
  else
    pre=""
    q="${ref#*/} doesn't say which port it listens on. Type it (like 8080), or local:port like 3000:8080. $PORT_RANGE_TXT"
  fi
  mode=ask pending="forward $ns $ref $ports"; list_save
  printf '%s' "$q" >"$S/question"
  list_todo "$(list_ask "$q" "$pending" "$pre" "port: ")"
}

job_lookup_scale() {   # ns name query
  local ns="$1" name="$2" now note
  saved_q=$3
  local f; f=$(mktemp)
  gitops_line "$ns" "$wkind" "$name" >"$f" &
  now=$(kubectl get "$wkind" "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  wait; note=$(<"$f"); rm -f "$f"
  local q="How many pods for $name? It has ${now:-?} now; 0 stops it."
  printf '%s' "$q" >"$S/question"
  list_todo "$(list_ask "$q" "scale $ns $name ${now:-?}" "${now:-}" "pods: " "$note")"
}

job_lookup_delete() {   # ns name query
  local ns="$1" name="$2" owner note=""
  saved_q=$3
  local f; f=$(mktemp)
  gitops_line "$ns" "$kind" "$name" >"$f" &
  if [[ "$kind" == pods ]]; then
    owner=$(kubectl get pod "$name" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    if [[ -n "$owner" ]]; then note="${C_DIM}Its $owner starts a new pod, so this works like a restart.${C_RESET}"
    else note="${C_RED}Nothing manages $name: it won't come back.${C_RESET}"; fi
  fi
  local g; wait; g=$(<"$f"); rm -f "$f"
  [[ -n "$g" ]] && note+="${note:+$'\n'}$g"
  list_todo "$(list_change_confirm "Delete $kind/$name in namespace $ns?" "delete $ns $name" "$name" "$note")"
}

job_can_i() {
  local -a scope=(-n "$ns"); (( all )) && scope=(-A)
  local e d f; f=$(mktemp)
  kubectl auth can-i update "$kind" "${scope[@]}" >"$f" 2>/dev/null &
  d=$(kubectl auth can-i delete "$kind" "${scope[@]}" 2>/dev/null)
  wait; e=$(<"$f"); rm -f "$f"
  can_edit=0 can_delete=0
  [[ "$e" == yes ]] && can_edit=1
  [[ "$d" == yes ]] && can_delete=1
  mode=list
  if (( can_edit || can_delete )); then changes=1; list_save; list_todo "print(@kx:relaunch)+accept"
  else list_save; list_todo "$(list_footer "${C_YELLOW}Your access on $(current_ctx) can only read $kind here, so change mode stays off.${C_RESET}" toast)"; fi
}

job_restart_pod() {   # ns pod
  local ns="$1" pod="$2" owner
  owner=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
  if [[ -z "$owner" ]]; then
    list_todo "$(list_footer "${C_RED}✗ Nothing manages $pod, so it wouldn't come back. Not touched.${C_RESET}" toast)"; return
  fi
  if kubectl delete pod "$pod" -n "$ns" --wait=false >/dev/null 2>&1; then
    list_todo "$(fzj "$(list_footer "${C_GREEN}✓${C_RESET} $pod is being replaced · its $owner starts a fresh pod" toast)" "$(list_reload)")"
    sleep 4; list_todo "$(list_reload)"; sleep 6; list_todo "$(list_reload)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't restart $pod (kubectl delete failed).${C_RESET}" toast)"
  fi
}

# Restart a workload and report progress until its new pods are ready.
job_restart_workload() {   # ns kind name
  local ns="$1" k="$2" name="$3" i msg
  if ! kubectl rollout restart "$k/$name" -n "$ns" >/dev/null 2>&1; then
    list_todo "$(list_footer "${C_RED}✗ Couldn't restart $name.${C_RESET}" toast)"; return
  fi
  for ((i = 0; i < 150; i++)); do
    if msg=$(kubectl rollout status "$k/$name" -n "$ns" --watch=false 2>&1) && [[ "$msg" == *"successfully rolled out"* ]]; then
      list_todo "$(fzj "$(list_footer "${C_GREEN}✓${C_RESET} $name restarted · its new pods are ready" toast)" "$(list_reload)")"
      return
    fi
    msg=$(sed -E 's/^Waiting for (deployment|statefulset|daemon set|daemonset) "[^"]*" rollout to finish: //; s/\.\.\.$//' <<<"$msg" | head -1)
    list_todo "$(fzj "$(list_footer "${C_YELLOW}Restarting $name…${C_RESET} ${C_DIM}$msg${C_RESET}")" "$(list_reload)")"
    sleep 2
  done
  list_todo "$(list_footer "${C_YELLOW}$name is still restarting after 5 minutes · check it with: kx why${C_RESET}" toast)"
}

job_delete() {   # ns name
  if kubectl delete "$kind" "$2" -n "$1" --wait=false >/dev/null 2>&1; then
    log_change "delete $kind/$2 -n $1"
    list_todo "$(fzj "$(list_footer "${C_GREEN}✓${C_RESET} Deleted $kind/$2" toast)" "$(list_reload)")"
    sleep 4; list_todo "$(list_reload)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't delete $kind/$2.${C_RESET}" toast)"
  fi
}

job_scale() {   # ns name from to
  if kubectl scale "$wkind/$2" -n "$1" --replicas="$4" >/dev/null 2>&1; then
    log_change "scale $wkind/$2 -n $1 $3→$4"
    list_todo "$(fzj "$(list_footer "${C_GREEN}✓${C_RESET} $2: $4 pods (was $3)" toast)" "$(list_reload)")"
    sleep 4; list_todo "$(list_reload)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't scale $2.${C_RESET}" toast)"
  fi
}

job_forward() {   # ns ref lport remote
  if forward_in_tab "$1" "$2" "$3" "$4"; then
    list_todo "$(list_footer "${C_GREEN}✓${C_RESET} http://localhost:$3 → ${2#*/} port $4 · in its own tab, close it to stop" toast)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't open a kitty tab.${C_RESET} ${C_DIM}Reload kitty's config (ctrl+shift+F5), then try again.${C_RESET}" toast)"
  fi
}

job_logs() {   # ns pod
  if logs_in_tab "$1" "$2"; then
    list_todo "$(list_footer "${C_GREEN}✓${C_RESET} Logs of $2 · in its own tab, q closes it" toast)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't open a kitty tab.${C_RESET} ${C_DIM}Reload kitty's config (ctrl+shift+F5), then try again.${C_RESET}" toast)"
  fi
}

job_shell() {   # ns pod
  if shell_in_tab "$1" "$2"; then
    list_todo "$(list_footer "${C_GREEN}✓${C_RESET} Shell inside $2 · in its own tab, exit to close it" toast)"
  else
    list_todo "$(list_footer "${C_RED}✗ Couldn't open a kitty tab.${C_RESET} ${C_DIM}Reload kitty's config (ctrl+shift+F5), then try again.${C_RESET}" toast)"
  fi
}

# One line about Flux / Argo CD putting the thing back from git (or nothing).
gitops_line() {   # ns kind name
  local l
  l=$(kubectl get "$2" "$3" -n "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null)
  case "$l" in
    *kustomize.toolkit.fluxcd.io*|*helm.toolkit.fluxcd.io*)
      printf '%s' "${C_YELLOW}Flux manages $3: it puts it back from git within minutes. Change it in git to make it stick.${C_RESET}" ;;
    *argocd.argoproj.io*)
      printf '%s' "${C_YELLOW}Argo CD manages $3: it may put it back from git. Change it in git to make it stick.${C_RESET}" ;;
  esac
}
