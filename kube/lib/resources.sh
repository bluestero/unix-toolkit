# kx resources: look at what runs in a cluster (pods, deployments, configs,
# secrets, services, events, any kind). Sourced by kube/bin/kx; uses its
# helpers (current_ctx, SELF) and lib/ui.sh.
#
# Every list is the same picker over `kubectl get <kind>`:
#   - it starts on this terminal's namespace; ctrl-a flips to every namespace
#     (and back), -n <namespace> looks at another one. Neither switches the terminal.
#   - details and values show in a pane on the right (ctrl-p), never a new screen.
#   - logs open in a scrollable viewer (q: back); port-forward gets its own
#     kitty tab so the list stays usable; a shell runs until you exit it.
#   - restart is always there (it asks). Edit, delete and scale only show after
#     ctrl-e turns on "change mode" for that list: the frame turns amber (red on
#     prod), edits show a diff before applying, prod asks you to type the name,
#     and every change goes in ~/.local/state/kx/changes.log (kx changes).

RES_SELECTOR=""   # label selector for the next list (the pods of one deployment)
RES_NS=""         # namespace for the next list ("" = this terminal's)

cur_ns() {
  local n; n=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)
  printf '%s' "${n:-default}"
}

need_ctx() { [[ -n "$(current_ctx)" ]] || die "No current context. Pick one with 'kx'."; }

# Decided once at start: inside $(...) stdout is always a pipe.
RES_TTY=0; [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null && RES_TTY=1
interactive() { (( RES_TTY )); }

# Runs a long command (logs -f, shell, port-forward) so ctrl-c stops just it.
until_ctrl_c() { trap ':' INT; "$@"; trap - INT; }

colorize() {
  [[ -n "$C_RESET" ]] || { cat; return; }
  local g=$C_GREEN y=$C_YELLOW r=$C_RED x=$C_RESET b=$'\e[1;97m'
  sed -E "1s/.*/$b&$x/
    1!{
    s/\b(CrashLoopBackOff|Error|ImagePullBackOff|ErrImagePull|OOMKilled|Failed|Evicted|NotReady|CreateContainerConfigError|BackOff|Warning)\b/$r&$x/g
    s/\b(Pending|ContainerCreating|PodInitializing|Terminating|Unknown|SchedulingDisabled|Init:[^ ]+)/$y&$x/g
    s/\b(Running|Ready|Active|Bound|Completed|Complete|Succeeded|Normal)\b/$g&$x/g
  }"
}

# Usage: res_rows <kind> <all 0|1> <namespace>
# kubectl get as "namespace<TAB>name<TAB>cells"; the header row has empty ids.
# The cells (\x1f-separated, never cut) are laid out by ui_fzf for the window it has,
# and again on a resize. Returns 2 when there are none.
res_rows() {
  local kind="$1" all="$2" ns="$3" out
  local -a args=(-n "$ns")
  (( all )) && args=(-A)
  [[ -n "$RES_SELECTOR" ]] && args+=(-l "$RES_SELECTOR")
  out=$(timeout 30 kubectl get "$kind" "${args[@]}" 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
  [[ -z "$out" || "$out" == "No resources found"* ]] && return 2
  printf '%s\n' "$out" | colorize | ui_split_cols | awk -v ns="$ns" 'BEGIN { OFS = "\t" }
    { l = $0; gsub(/\033\[[0-9;]*m/, "", l); split(l, f, "\037") }
    NR == 1 { all = (f[1] == "NAMESPACE"); print "", "", $0; next }
    { if (all) print f[1], f[2], $0; else print ns, f[1], $0 }'
}

# What each kind's list does. Set by kind_setup:
#   PK_HEADER  key hints for its own keys (ctrl-p, ctrl-a, ctrl-e and esc are added)
#   PK_PANE    what the details pane shows: describe | values
#   PK_ACT     what the keys do (list.sh): pods | workloads | values | services |
#              generic, or single-logs / -shell / -why / -restart (enter runs it, then done)
#   PK_SCALE   1 when change mode can scale it
kind_setup() {
  PK_PANE=describe PK_SCALE=0 PK_ACT=generic
  case "$1" in
    pods)
      PK_HEADER="enter: logs · ctrl-s: shell inside · ctrl-f: port-forward · ctrl-r: restart" PK_ACT=pods ;;
    deployments|statefulsets|daemonsets)
      PK_HEADER="enter: its pods · ctrl-l: logs of all its pods · ctrl-r: restart" PK_ACT=workloads
      [[ "$1" == daemonsets ]] || PK_SCALE=1 ;;
    configmaps)
      PK_HEADER="enter: show / hide its settings" PK_PANE=values PK_ACT=values ;;
    secrets)
      PK_HEADER="enter: show / hide the values" PK_PANE=values PK_ACT=values ;;
    services)
      PK_HEADER="enter: port-forward to it" PK_ACT=services ;;
    *)
      PK_HEADER="enter: show / hide details" ;;
  esac
}

# browse (the list itself) lives in list.sh.

# Right-hand pane. Usage: kx __pane <describe|values> <kind> <namespace> <name>
res_pane() {
  local what="$1" kind="$2" ns="$3" name="$4"
  [[ -n "$name" ]] || return 0
  if [[ "$what" == values && "$kind" == secrets ]]; then
    is_prod "$(current_ctx)" && printf '%s\n\n' "$(ui_badge PROD) careful where these end up"
    kubectl get secret "$name" -n "$ns" -o go-template="{{range \$k, \$v := .data}}$C_CYAN{{\$k}}$C_RESET
{{\$v | base64decode}}

{{else}}(no values){{end}}" 2>&1
  elif [[ "$what" == values ]]; then
    kubectl get configmap "$name" -n "$ns" -o go-template="{{range \$k, \$v := .data}}$C_CYAN{{\$k}}$C_RESET
{{\$v}}

{{else}}(no settings){{end}}" 2>&1
  elif [[ "$kind" == pods ]]; then
    why_report "$ns" "$name"
    printf '\n%s\n\n' "${C_LINE}──── full details ────${C_RESET}"
    kubectl describe pod "$name" -n "$ns" 2>&1
  else
    kubectl describe "$kind" "$name" -n "$ns" 2>&1
  fi
}

# ------------------------------------------------------------------ pods ---

pick_container() {   # ns pod → a container name (asks when there are several)
  local cs
  cs=$(kubectl get pod "$2" -n "$1" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null)
  if [[ $(grep -c . <<<"$cs") -le 1 ]] || ! interactive; then printf '%s' "${cs%%$'\n'*}"; return; fi
  printf '%s\n' "$cs" | ui_fzf "containers in $2" --prompt='container> ' \
    --header='this pod runs more than one container · enter: pick'
}

# less prompt text: escape the characters less treats as prompt syntax.
less_prompt() { local t="$1"; t=${t//\\/\\\\}; t=${t//:/\\:}; t=${t//./\\.}; t=${t//\?/\\?}; t=${t//%/\\%}; printf '%s' "$t"; }

# Level words in JSON logs get a colour (sed script; less -R shows it).
LOG_COLORS='s/"level":"\(error\|fatal\|panic\)"/"level":"\x1b[31m\1\x1b[0m"/I;s/"level":"\(warn\|warning\)"/"level":"\x1b[33m\1\x1b[0m"/I;s/"level":"\(debug\|trace\)"/"level":"\x1b[90m\1\x1b[0m"/I'

# Usage: view_logs <follow 0|1> <title> <kubectl logs args...>
# Logs in less: scroll (mouse wheel too), / to search. Following: kubectl
# writes to a file in the background and less tails it, so ctrl-c only pauses
# (f follows again); q goes back to the list.
view_logs() {
  local follow="$1" title="$2" f pid; shift 2
  if ! [[ -t 1 ]] || ! command -v less >/dev/null; then kubectl logs "$@"; return; fi
  f=$(umask 077; mktemp "${TMPDIR:-/tmp}/kx-logs.XXXXXX")
  # -I: searches ignore case. lesskey: f follows too (not only F), and alt+backspace
  # or ctrl+backspace deletes a word while typing a search.
  local k="$f.key" q_what=back; [[ -n "${KX_TAB:-}" ]] && q_what="close this tab"
  printf '#command\nf forw-forever\n#line-edit\n\\e\\177 word-backspace\n\\b word-backspace\n' >"$k"
  lesskey -o "$k.bin" "$k" >/dev/null 2>&1
  local -a opts=(-R -I --mouse --wheel-lines=3)
  [[ -s "$k.bin" ]] && opts+=(-k "$k.bin")
  if (( follow )); then
    # less says only "Waiting for data... (interrupt to abort)" while following,
    # so the first line of the file tells how to stop.
    printf '%s\n' "── live logs · ctrl-c: pause and scroll · f: follow again · /: search · q: $q_what ──" >"$f"
    ( trap '' INT; exec kubectl logs -f "$@" 2>&1 | sed -u "$LOG_COLORS" ) >>"$f" 2>&1 &
    pid=$!
    opts+=(+F -Ps"$(less_prompt "$title · ctrl-c: pause and scroll · f: follow again · /: search · q: $q_what")")
  else
    kubectl logs "$@" >"$f" 2>&1
    opts+=(+G -Ps"$(less_prompt "$title · /: search · q: $q_what")")
  fi
  trap ':' INT
  less "${opts[@]}" "$f"
  trap - INT
  [[ -n "${pid:-}" ]] && { pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  rm -f "$f" "$k" "$k.bin"
}

# Live logs; for a crashing container, the logs of the run that crashed
# (the live ones are empty while it waits to restart).
pod_logs() {   # ns pod
  local ns="$1" pod="$2" c st restarts waiting reason code
  c=$(pick_container "$ns" "$pod") || return 0
  st=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.containerStatuses[?(@.name=='$c')].restartCount} {.status.containerStatuses[?(@.name=='$c')].state.waiting.reason} {.status.containerStatuses[?(@.name=='$c')].lastState.terminated.reason} {.status.containerStatuses[?(@.name=='$c')].lastState.terminated.exitCode}" 2>/dev/null)
  read -r restarts waiting reason code <<<"$st"
  if [[ "${restarts:-0}" -gt 0 && -n "$waiting" ]]; then
    view_logs 0 "CRASHING ($waiting, $restarts restarts) · logs of its last run${reason:+, ended with $reason}${code:+ exit $code}" \
      "$pod" -n "$ns" ${c:+-c "$c"} --previous --tail=2000
    return 0
  fi
  view_logs 1 "$pod${c:+ ($c)} live" --tail=1000 "$pod" -n "$ns" ${c:+-c "$c"}
}

pod_shell() {   # ns pod [asked: the prod question was already answered]
  local ns="$1" pod="$2" c
  if is_prod "$(current_ctx)" && [[ "${3:-}" != asked ]]; then
    warn "$(ui_badge PROD) a shell inside $pod can change the running app."
    confirm "Open it anyway?" n || return 0
  fi
  c=$(pick_container "$ns" "$pod") || return 0
  info "${C_DIM}Shell inside $pod${c:+ ($c)} · exit: ${KX_SHELL_TAB:+close this tab}${KX_SHELL_TAB:-back to the list}${C_RESET}"
  kubectl exec -it "$pod" -n "$ns" ${c:+-c "$c"} -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}

cmd_pods() { kind_setup pods; browse pods "$@"; }

# kx logs [filter | deploy/<name>] [-A] [-n ns]
cmd_logs() {
  if [[ "${1:-}" == */* ]]; then
    need_ctx
    local ns; ns=$(cur_ns)
    workload_logs "$ns" "$1"
    return
  fi
  kind_setup pods
  PK_HEADER="enter: follow its logs" PK_ACT=single-logs browse pods "$@"
}

cmd_shell() {
  kind_setup pods
  PK_HEADER="enter: open a shell inside" PK_ACT=single-shell browse pods "$@"
}

# ------------------------------------------------------------------- why ---

# kx why [pod] [-A] [-n ns]: why a pod isn't healthy, in plain words: what's
# wrong, what usually causes it, the last lines it printed, recent warnings.
cmd_why() {
  need_ctx
  if [[ -n "${1:-}" && "$1" != -* ]] && kubectl get pod "$1" -n "$(cur_ns)" >/dev/null 2>&1; then
    why_report "$(cur_ns)" "$1"; return
  fi
  kind_setup pods
  PK_HEADER="enter: why it's unhealthy" PK_ACT=single-why browse pods "$@"
}

# What an exit code usually means.
exit_meaning() {
  case "$1" in
    0)   echo "it finished normally, but it's meant to keep running" ;;
    1)   echo "the app stopped with an error (its last lines below usually say which)" ;;
    2)   echo "the app stopped with an error, often a wrong setting or argument" ;;
    126) echo "its start command can't run (permissions, or not a program)" ;;
    127) echo "its start command wasn't found in the image" ;;
    137) echo "it was killed: out of memory, or it didn't stop in time when asked" ;;
    139) echo "it crashed (segmentation fault)" ;;
    143) echo "it was asked to stop (SIGTERM), e.g. a restart or a failed health check" ;;
    *)   echo "the app stopped with exit code $1" ;;
  esac
}

# Usage: why_report <ns> <pod>. Boxed on a terminal; plain in the details pane.
why_report() {
  local ns="$1" pod="$2" w all head phase reason msg sched_ok sched_reason sched_msg deleting rows
  w=$(( $(ui_cols) - 12 )); (( w > 90 )) && w=90; (( w < 30 )) && w=30   # the text column
  # Warnings come from another call: start it now, read it at the end.
  local evf; evf=$(mktemp)
  kubectl get events -n "$ns" --field-selector "involvedObject.name=$pod,type=Warning" \
    --sort-by=.lastTimestamp -o jsonpath='{range .items[*]}{.reason}{"\t"}{.count}{"\t"}{.message}{"\n"}{end}' >"$evf" 2>/dev/null &
  local evpid=$!
  # Everything else in one call: line 1 the pod, then one line per container
  # (kind name ready restarts waitReason waitMsg termReason termCode lastReason
  # lastCode lastAt, plus its memory limit), then the pod's message.
  local c='{.name}{"\t"}{.ready}{"\t"}{.restartCount}{"\t"}{.state.waiting.reason}{"\t"}{.state.waiting.message}{"\t"}{.state.terminated.reason}{"\t"}{.state.terminated.exitCode}{"\t"}{.lastState.terminated.reason}{"\t"}{.lastState.terminated.exitCode}{"\t"}{.lastState.terminated.finishedAt}{"\n"}'
  all=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.phase}{\"\t\"}{.status.reason}{\"\t\"}{.metadata.deletionTimestamp}{\"\t\"}{range .status.conditions[?(@.type==\"PodScheduled\")]}{.status}{\"\t\"}{.reason}{\"\t\"}{.message}{end}{\"\n\"}{range .status.initContainerStatuses[*]}init{\"\t\"}$c{end}{range .status.containerStatuses[*]}main{\"\t\"}$c{end}@msg{\"\t\"}{.status.message}" 2>&1) ||
    { kill "$evpid" 2>/dev/null; rm -f "$evf"; warn "$all"; return 1; }
  # Fields are tab-separated, read with \x1f: bash collapses empty fields between tabs.
  local US=$'\x1f'
  head=$(head -1 <<<"$all")
  IFS=$US read -r phase reason deleting sched_ok sched_reason sched_msg <<<"$(tr '\t' "$US" <<<"$head")"
  rows=$(sed -n '2,$p' <<<"$all" | sed '/^@msg\t/,$d' | grep -E '^(init|main)	' | tr '\t' "$US")
  msg=$(sed -n '/^@msg\t/,$p' <<<"$all" | sed '1s/^@msg\t//' | tr '\n' ' ')

  local verdict="" why="" logs_c="" logs_prev=0 total=0 ready=0 restarts=0
  local k n rd rc wr wm tr tc lr lc la limit
  while IFS=$US read -r k n rd rc wr wm tr tc lr lc la; do
    [[ -n "$n" ]] || continue
    if [[ "$k" == main ]]; then total=$((total + 1)); [[ "$rd" == true ]] && ready=$((ready + 1)); fi
    restarts=$((restarts + ${rc:-0}))
    [[ -n "$verdict" ]] && continue   # explain the first container with a problem
    local who="$n"; [[ "$k" == init ]] && who="$n (runs before the app starts)"
    case "$wr" in
      CrashLoopBackOff)
        verdict="CRASHING · $who"
        why="It starts, then stops, again and again. Kubernetes keeps restarting it and waits longer each time (up to 5 minutes)."
        if [[ "$lr" == OOMKilled ]]; then
          limit=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[?(@.name==\"$n\")].resources.limits.memory}" 2>/dev/null)
          why+=" Its last run used more memory than its limit${limit:+ ($limit)} and was killed."
        elif [[ -n "$lc" ]]; then why+=" Its last run ended with exit $lc: $(exit_meaning "$lc")."; fi
        logs_c=$n logs_prev=1 ;;
      ImagePullBackOff|ErrImagePull|InvalidImageName)
        verdict="CAN'T GET ITS IMAGE · $who"
        why="Kubernetes can't download the app's image: the name or tag may be wrong, or the cluster has no access to that registry. ${wm}" ;;
      CreateContainerConfigError)
        verdict="MISSING SETTINGS · $who"
        why="Something it needs to start is missing, usually a secret or configmap it refers to. ${wm}" ;;
      CreateContainerError|RunContainerError)
        verdict="WON'T START · $who"; why="The container couldn't be started. ${wm}" ;;
      ContainerCreating|PodInitializing)
        verdict="STARTING · $who"
        why="Still starting: downloading the image or attaching storage. If it stays like this, the warnings below say why." ;;
      "")
        if [[ -n "$tr" && "$tr" != Completed && "$k" == main ]]; then
          verdict="STOPPED · $who"; why="It stopped: $tr, exit ${tc:-?}: $(exit_meaning "${tc:-1}")."; logs_c=$n
        elif [[ "$k" == main && "$rd" != true && -z "$tr" && "$phase" == Running ]]; then
          verdict="NOT READY · $who"
          why="It's running, but its readiness check is failing, so it gets no traffic. The warnings below show what the check gets back."
          logs_c=$n
        elif [[ "$k" == main && "${rc:-0}" -gt 0 && -n "$lr" ]]; then
          verdict="RESTARTED · $who"
          why="Running now, but it has restarted $rc times. The last restart: $lr, exit ${lc:-?}: $(exit_meaning "${lc:-1}")."
          [[ "$lr" == OOMKilled ]] && why="Running now, but it has restarted $rc times, last because it ran out of memory (OOMKilled)."
          logs_c=$n logs_prev=1
        fi ;;
      *) verdict="${wr^^} · $who"; why="${wm:-Waiting: $wr.}" ;;
    esac
  done <<<"$rows"

  # Pod-level problems win over container ones.
  if [[ -n "$deleting" ]]; then
    verdict="BEING DELETED"; why="It was asked to stop and is shutting down. If it stays like this, something is holding it (a finalizer, or the node is gone)."
  elif [[ "$reason" == Evicted ]]; then
    verdict="EVICTED"; why="The machine it ran on got low on resources and pushed it out. ${msg}"
  elif [[ "$phase" == Pending && "$sched_ok" == False ]]; then
    verdict="CAN'T BE PLACED"
    case "$sched_msg" in
      *persistentvolumeclaim*"not found"*)
        why="The storage it asks for (a PersistentVolumeClaim) doesn't exist, so no machine can run it. Create the claim, or fix its name in the app's settings." ;;
      *Insufficient*)
        why="Every machine (node) that may run it is full: not enough free CPU or memory for what it asks. It starts when room frees up or the cluster adds a machine." ;;
      *affinity*|*selector*|*taint*)
        why="It asks for a particular kind of machine (node), and none of those is free. Usually its node settings or the cluster's node groups need a look." ;;
      *) why="No machine (node) in the cluster can take it right now." ;;
    esac
    why+=" Kubernetes says: ${sched_msg}"
  elif [[ "$phase" == Succeeded ]]; then
    verdict="FINISHED"; why="It ran to the end and stopped. That's normal for jobs."
  elif [[ "$phase" == Failed && -z "$verdict" ]]; then
    verdict="FAILED"; why="It stopped and won't be restarted. ${msg}"
  fi

  local -a out=()
  if [[ -z "$verdict" ]]; then
    out+=("status	${C_GREEN}HEALTHY${C_RESET} · running, $ready/$total ready${restarts:+, $restarts restarts}")
  else
    local col=$C_RED; [[ "$verdict" == STARTING* || "$verdict" == RESTARTED* || "$verdict" == FINISHED* ]] && col=$C_YELLOW
    out+=("status	${col}${C_BOLD}${verdict}${C_RESET}")
    (( total )) && out+=("ready	$ready of $total containers · $restarts restarts")
    local first=1 line
    while IFS= read -r line; do
      if (( first )); then out+=("why	$line"); first=0; else out+=(" 	$line"); fi
    done < <(fold -s -w "$w" <<<"$why")
  fi
  out+=("where	$(current_ctx) · namespace $ns")
  printf '%s\n' "${out[@]}" | ui_fields "kx why · $pod"

  if [[ -n "$logs_c" ]]; then
    local -a la=(--tail=300 -c "$logs_c"); (( logs_prev )) && la+=(--previous)
    # The error is often not in the very last lines (a config dump, a stack
    # trace's tail), so show the last lines that look like errors, if any.
    local all lines title
    all=$(kubectl logs "$pod" -n "$ns" "${la[@]}" 2>/dev/null)
    lines=$(grep -iE 'error|exception|fatal|panic|caused by|traceback|failed|refused|denied|timed? ?out' <<<"$all" | tail -8)
    if [[ -n "$lines" ]]; then title="Errors in its last 300 log lines"
    else lines=$(tail -10 <<<"$all"); title="Last lines it printed"; fi
    (( logs_prev )) && title+=" (its run before this one)"
    if [[ -n "$lines" ]]; then
      echo; printf '%s\n' "${C_BOLD}$title${C_RESET}"
      cut -c1-$(( w + 18 )) <<<"$lines" | sed "s/^/  ${C_DIM}│${C_RESET} /"
    fi
  fi
  local ev
  wait "$evpid" 2>/dev/null
  # One line per kind of warning (the latest); old "couldn't place it" ones
  # are dropped once the pod has a machine.
  ev=$(awk -F'\t' -v placed="$sched_ok" 'NF && !(placed == "True" && $1 == "FailedScheduling")' "$evf" |
        tac | awk -F'\t' '!seen[$1]++' | tac | tail -5)
  rm -f "$evf"
  if [[ -n "$ev" ]]; then
    echo; printf '%s\n' "${C_BOLD}Recent warnings${C_RESET}"
    while IFS=$'\t' read -r k n line; do
      ui_fit "  $C_YELLOW$k$C_RESET ${C_DIM}$( [[ "${n:-1}" -gt 1 ]] && echo "×$n ")${C_RESET}$line" $(( $(ui_cols) - 2 )); echo
    done <<<"$ev"
  fi
  if [[ -n "$verdict" && -t 1 ]]; then
    echo; printf '%s\n' "${C_DIM}More: kx logs $pod · kx events${C_RESET}"
  fi
}

# --------------------------------------------------- deployments & co. ---

workload_selector() {   # ns kind/name → "k=v,k=v"
  local s
  s=$(kubectl get "$2" -n "$1" -o go-template='{{range $k, $v := .spec.selector.matchLabels}}{{$k}}={{$v}},{{end}}' 2>/dev/null) || return 1
  [[ -n "$s" ]] && printf '%s' "${s%,}"
}

workload_logs() {   # ns kind/name
  local sel
  sel=$(workload_selector "$1" "$2") || { warn "No $2 in namespace $1."; return 0; }
  view_logs 1 "every pod of ${2#*/} live" --tail=200 -n "$1" -l "$sel" --all-containers --prefix --max-log-requests=20
}

workload_restart() {   # ns kind name  (asks first)
  is_prod "$(current_ctx)" && warn "$(ui_badge PROD) $(current_ctx)"
  confirm "Restart $3? Its pods are replaced one at a time, so it stays up." n || return 0
  workload_restart_fg "$@"
}
workload_restart_fg() {   # ns kind name  (already asked)
  local ns="$1" kind="$2" name="$3"
  kubectl rollout restart "$kind/$name" -n "$ns" >/dev/null || return 0
  info "${C_DIM}Waiting for the new pods · ctrl-c stops watching (the restart carries on)${C_RESET}"
  until_ctrl_c timeout 300 kubectl rollout status "$kind/$name" -n "$ns"
}

WORKLOAD_KIND=deployments

cmd_workloads() {   # kind [args]
  local kind="$1"; shift
  kind_setup "$kind"
  WORKLOAD_KIND="$kind" browse "$kind" "$@"
}
cmd_deploys() { cmd_workloads deployments "$@"; }

cmd_restart() {
  if [[ $# -eq 0 ]]; then
    kind_setup deployments
    PK_HEADER="enter: restart it" PK_ACT=single-restart browse deployments
    return
  fi
  need_ctx
  local t="$1"; [[ "$t" == */* ]] || t="deployment/$t"
  workload_restart "$(cur_ns)" "${t%%/*}" "${t#*/}"
}

# ------------------------------------------------------ configs & secrets ---

cmd_configs() { kind_setup configmaps; browse configmaps "$@"; }
cmd_secrets() { kind_setup secrets; browse secrets "$@"; }

# ----------------------------------------------------- services, forward ---

cmd_services() { kind_setup services; browse services "$@"; }

# Usage: do_forward <ns> <kind/name> [[local:]remote]
# Without a port: lists the ports the pod/service says it listens on (from its
# spec), with the port on this computer filled in, so enter forwards and typing
# another number picks your own.
do_forward() {
  local ns="$1" ref="$2" port="${3:-}" path remote lport want="" out q row n
  local -a rows=()
  if [[ -z "$port" ]]; then
    case "$ref" in
      service/*|svc/*) path='{range .spec.ports[*]}{.port}{"\t"}{.name}{"\n"}{end}' ;;
      pod/*)           path='{range .spec.containers[*]}{range .ports[*]}{.containerPort}{"\t"}{.name}{"\n"}{end}{end}' ;;
      *)               path='{range .spec.template.spec.containers[*]}{range .ports[*]}{.containerPort}{"\t"}{.name}{"\n"}{end}{end}' ;;
    esac
    mapfile -t rows < <(kubectl get "$ref" -n "$ns" -o jsonpath="$path" 2>/dev/null | awk -F'\t' 'NF && !seen[$1]++')
    if (( ${#rows[@]} == 0 )); then
      interactive || { warn "${ref#*/} doesn't list its ports. Say which: kx forward $ref <port>"; return 0; }
      port=$(ui_ask "${ref#*/} doesn't list its ports. Which port does it listen on?") || return 0
    elif ! interactive; then
      port=${rows[0]%%$'\t'*}
    else
      local -a shown=()
      local what=pod; [[ "$ref" == service/* || "$ref" == svc/* ]] && what=service
      for row in "${rows[@]}"; do   # "9001<tab>http" -> "9001<tab>→ port 9001 in the pod  (http)"
        n=${row%%$'\t'*}; row=${row#*$'\t'}
        shown+=("$n"$'\t'"→ port $n in the $what${row:+  ${C_DIM}($row)${C_RESET}}")
      done
      # One port: the number on this computer is filled in, keep it or type
      # another. Several: empty, so each row uses its own number.
      local busy=""
      if (( ${#rows[@]} == 1 )); then
        n=$(local_for "${rows[0]%%$'\t'*}"); q=$(free_port "$n")
        [[ "$q" != "$n" ]] && busy="!localhost:$n is taken (another forward?), so $q instead"$'\n'
      else q=""; fi
      out=$(printf '%s\n' "${shown[@]}" |
        ui_fzf "kx forward · ${ref#*/}" --disabled --print-query --query="$q" --info=hidden \
          --delimiter='\t' --with-nth=2 --prompt='localhost:' \
          --header="$busy""enter: forward · type a number: use that port on this computer (1024–65535) · esc: back") || return 0
      want=$(sed -n 1p <<<"$out"); row=$(sed -n 2p <<<"$out")
      [[ -z "$want" || "$want" =~ ^[0-9]+$ ]] || { warn "Not a port number: '$want'"; return 0; }
      port="${want:+$want:}${row%%$'\t'*}"
    fi
  fi
  [[ "$port" =~ ^([0-9]+:)?[0-9]+$ ]] || { warn "Not a port: '$port'"; return 0; }
  remote=${port#*:}
  if [[ "$port" == *:* ]]; then
    lport=${port%%:*}
    if port_busy "$lport"; then
      n=$(free_port "$lport")
      warn "localhost:$lport is already in use. Nearest free: $n · $PORT_RANGE_TXT"
      info "    Try: kx forward $ref $n:$remote"; return 0
    fi
  else
    lport=$(free_port "$(local_for "$remote")")
  fi
  if forward_in_tab "$ns" "$ref" "$lport" "$remote"; then
    ok "http://localhost:$lport  ${C_DIM}goes to ${ref#*/} port $remote · runs in its own tab, close it to stop${C_RESET}"
  else   # not in kitty: full screen here, and the screen comes back clean after ctrl-c
    tput smcup 2>/dev/null; clear
    trap ':' INT
    forward_screen "$ns" "$ref" "$lport" "$remote" "ctrl-c (back to the list)"
    trap - INT
    tput rmcup 2>/dev/null
  fi
}

# Same number on this computer, except ports under 1024 (those need root): +8000.
local_for() { if (( $1 < 1024 )); then echo $(( $1 + 8000 )); else echo "$1"; fi; }
free_port() { local p="$1"; while port_busy "$p"; do p=$((p + 1)); done; echo "$p"; }
# Shown wherever a local port is asked for: under 1024 needs root, so 1024 and up.
PORT_RANGE_TXT="Free local ports: 1024–65535."

# "weave-gitops-b94547df9-gg7wn" -> "weave-gitops": drops the random endings
# Kubernetes adds to pod names, for short tab titles.
short_name() {
  sed -E 's/-[a-z0-9]{6,10}-[a-z0-9]{5}$//; t; s/-[a-z0-9]{5}$//' <<<"$1" | cut -c1-24
}

port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# kitty can open the port-forward in a new tab, next to this one. Needs the
# "kx" remote control password in kitty.conf (work-toolkit's kitty.conf has it).
# Run a kx command in a new kitty tab, with this shell's cluster and AWS profile.
kitty_tab() {   # title keep-focus|focus kx-args...
  [[ -n "${KITTY_WINDOW_ID:-}" && -n "${KITTY_LISTEN_ON:-}" ]] || return 1
  local k; k=$(command -v kitty 2>/dev/null || echo "$HOME/.local/kitty.app/bin/kitty")
  [[ -x "$k" ]] || return 1
  local title="$1" focus="$2"; shift 2
  local -a opt=()
  [[ "$focus" == keep-focus ]] && opt+=(--keep-focus)
  [[ -n "${KUBECONFIG:-}" ]] && opt+=(--env "KUBECONFIG=$KUBECONFIG")
  [[ -n "${AWS_PROFILE:-}" ]] && opt+=(--env "AWS_PROFILE=$AWS_PROFILE")
  "$k" @ --password=kx launch --type=tab --tab-title "$title" "${opt[@]}" "$SELF" "$@" >/dev/null 2>&1
}

forward_in_tab() {   # ns ref lport remote
  kitty_tab "⇄ $(short_name "${2#*/}") :$3" keep-focus __forward "$1" "$2" "$3" "$4"
}

shell_in_tab() {   # ns pod
  kitty_tab "› $(short_name "$2")" focus __shell "$1" "$2"
}
logs_in_tab() {   # ns pod
  kitty_tab "≡ $(short_name "$2") · ctrl-c: pause" focus __logs "$1" "$2"
}
# What runs in that tab. A shell that fails to start keeps the tab open so
# you can read why.
shell_tab() {   # ns pod
  local t=$SECONDS
  pod_shell "$1" "$2" asked && return
  (( SECONDS - t < 5 )) && { echo; read -r -p "Press enter to close this tab. " _; }
}

# What a port-forward shows while it runs (in its tab, or full screen here).
forward_screen() {   # ns ref lport remote how-to-stop
  {
    printf 'open\t%s\n' "${C_BOLD}http://localhost:$3${C_RESET}"
    printf 'goes to\t%s\n' "${2#*/} port $4"
    printf 'where\t%s\n' "$(current_ctx) · namespace $1"
    printf 'stop\t%s\n' "$5"
  } | ui_fields "kx forward"
  echo
  if [[ "$5" == ctrl-c* ]]; then
    kubectl port-forward -n "$1" "$2" "$3:$4" 2>&1 | grep --line-buffered -v '^Handling connection'
  else
    kubectl port-forward -n "$1" "$2" "$3:$4" 2>&1 | grep --line-buffered -v '^Handling connection'
    echo; warn "The port-forward stopped (the pod restarted, or the connection dropped)."
    read -r -p "Press enter to close this tab. " _
  fi
}

# kx forward <pod|svc/name|deploy/name> [[local:]remote]
cmd_forward() {
  need_ctx
  case "${1:-}" in
    "") cmd_services ;;
    */*) do_forward "$(cur_ns)" "$1" "${2:-}" ;;
    *) do_forward "$(cur_ns)" "pod/$1" "${2:-}" ;;
  esac
}

# ------------------------------------------------------------ details pane ---

# ------------------------------------------------------------ change mode ---

CHANGES_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/kx/changes.log"

log_change() {   # what
  mkdir -p "$(dirname "$CHANGES_LOG")"
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$(current_ctx)" "$1" >>"$CHANGES_LOG"
}

# dev: y/N (default no). prod: type the name.
confirm_change() {   # question name
  local reply
  [[ -t 0 ]] || return 1
  if is_prod "$(current_ctx)"; then
    reply=$(UI_CONFIRM_LABEL="PROD · $(current_ctx)" ui_ask "$1 Type $2 to confirm (anything else cancels).") || reply=""
    [[ "$reply" == "$2" ]] && return 0
  else
    confirm "$1" n && return 0
  fi
  info "Cancelled."; return 1
}

# Flux / Argo CD put things back from git: say so before a change.
gitops_note() {   # ns kind name
  local l
  l=$(kubectl get "$2" "$3" -n "$1" -o jsonpath='{.metadata.labels}' 2>/dev/null)
  case "$l" in
    *kustomize.toolkit.fluxcd.io*|*helm.toolkit.fluxcd.io*)
      warn "Flux manages $3: it puts it back from git within minutes. Change it in git to make it stick." ;;
    *argocd.argoproj.io*)
      warn "Argo CD manages $3: it may put it back from git. Change it in git to make it stick." ;;
  esac
}

# Edit a copy, see the diff, then apply (plain kubectl edit applies on save).
change_edit() {   # ns kind name
  local ns="$1" kind="$2" name="$3" dir f ed d rc
  dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/kx-edit.XXXXXX"); f="$dir/$name.yaml"
  kubectl get "$kind" "$name" -n "$ns" -o yaml >"$f" 2>/dev/null || { warn "Couldn't read $kind/$name."; rm -rf "$dir"; return 0; }
  cp "$f" "$dir/.orig"
  ed=${KUBE_EDITOR:-${VISUAL:-${EDITOR:-}}}
  [[ -n "$ed" ]] || { command -v nano >/dev/null && ed=nano || ed=vi; }
  $ed "$f" </dev/tty >/dev/tty
  if cmp -s "$f" "$dir/.orig"; then info "No changes made."; rm -rf "$dir"; return 0; fi
  d=$(kubectl diff -f "$f" 2>&1); rc=$?
  if (( rc == 0 )); then info "That wouldn't change anything on the cluster."; rm -rf "$dir"; return 0; fi
  if (( rc > 1 )); then warn "kubectl can't use that edit:"; printf '%s\n' "$d" >&2; rm -rf "$dir"; return 0; fi
  info "${C_BOLD}What will change on $kind/$name:${C_RESET}"
  printf '%s\n' "$d" | grep -v '^diff -u\|^--- \|^+++ ' | sed -E "s/^\+.*/$C_GREEN&$C_RESET/; s/^-.*/$C_RED&$C_RESET/; s/^@@.*/$C_CYAN&$C_RESET/" >&2
  gitops_note "$ns" "$kind" "$name"
  if confirm_change "Apply it?" "$name"; then
    kubectl replace -f "$f" >/dev/null && { ok "Updated $kind/$name."; log_change "edit $kind/$name -n $ns"; }
  fi
  rm -rf "$dir"
}

change_delete() {   # ns kind name
  local ns="$1" kind="$2" name="$3" owner=""
  if [[ "$kind" == pods ]]; then
    owner=$(kubectl get pod "$name" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    if [[ -n "$owner" ]]; then info "Its $owner starts a new pod, so this is a restart."
    else warn "Nothing manages $name: it won't come back."; fi
  fi
  gitops_note "$ns" "$kind" "$name"
  confirm_change "Delete $kind/$name in namespace $ns?" "$name" || return 0
  kubectl delete "$kind" "$name" -n "$ns" --wait=false >/dev/null && { ok "Deleted $kind/$name."; log_change "delete $kind/$name -n $ns"; }
}

change_scale() {   # ns kind name
  local ns="$1" kind="$2" name="$3" now n
  now=$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  n=$(ui_ask "How many pods for $name? (now ${now:-?}; 0 stops it)" "${now:-}") || return 0
  [[ "$n" =~ ^[0-9]+$ ]] || { info "Not a number; nothing changed."; return 0; }
  [[ "$n" == "$now" ]] && { info "Already $n."; return 0; }
  gitops_note "$ns" "$kind" "$name"
  confirm_change "Scale $name from ${now:-?} to $n pods?" "$name" || return 0
  kubectl scale "$kind/$name" -n "$ns" --replicas="$n" >/dev/null && { ok "$name: $n pods."; log_change "scale $kind/$name -n $ns ${now:-?}→$n"; }
}

cmd_changes() {
  [[ -s "$CHANGES_LOG" ]] || { info "No changes made with kx yet."; return 0; }
  [[ -t 1 ]] || ui_no_color
  { printf '%s\x1f%s\x1f%s\n' "${C_BOLD}WHEN${C_RESET}" "${C_BOLD}CONTEXT${C_RESET}" "${C_BOLD}WHAT${C_RESET}"
    tail -n 30 "$CHANGES_LOG" | tr '\t' '\037'; } | ui_table "kx · your last changes" "" "${CHANGES_LOG/#$HOME/\~}"
}

# ------------------------------------------------------- events, top, get ---

cmd_events() {
  need_ctx
  local -a args=()
  [[ "${1:-}" == -A || "${1:-}" == --all ]] && args+=(-A)
  [[ -t 1 ]] || ui_no_color
  kubectl get events "${args[@]}" --sort-by=.lastTimestamp 2>&1 | colorize
}

cmd_top() {
  need_ctx
  local what="${1:-pods}" out
  case "$what" in
    pods)  out=$(kubectl top pods --sort-by=memory 2>&1) ;;
    nodes) out=$(kubectl top nodes 2>&1) ;;
    *) die "Usage: kx top [pods|nodes]" ;;
  esac || { printf '%s\n' "$out" >&2; info "${C_DIM}kx top needs metrics-server on the cluster.${C_RESET}"; return 1; }
  printf '%s\n' "$out"
}

# kx get [kind] [-A] [-n ns] [filter] — any kind; the known ones get their own keys.
cmd_get() {
  need_ctx
  local kind="${1:-}"
  if [[ -z "$kind" || "$kind" == -* ]]; then
    interactive || { kubectl api-resources --verbs=list; return; }
    kind=$(kubectl api-resources --verbs=list 2>/dev/null | colorize |
      ui_fzf 'kx · kinds of thing on this cluster' --sortable --header-lines=1 --prompt='kind> ' \
        --header='enter: list them · esc: quit' | awk '{ print $1 }') || return 0
    [[ -n "$kind" ]] || return 0
  else
    shift
  fi
  case "$kind" in
    po|pod|pods)                   cmd_pods "$@" ;;
    deploy|deployment|deployments) cmd_deploys "$@" ;;
    sts|statefulset|statefulsets)  cmd_workloads statefulsets "$@" ;;
    ds|daemonset|daemonsets)       cmd_workloads daemonsets "$@" ;;
    cm|configmap|configmaps)       cmd_configs "$@" ;;
    secret|secrets)                cmd_secrets "$@" ;;
    svc|service|services)          cmd_services "$@" ;;
    *) kind_setup "$kind"; browse "$kind" "$@" ;;
  esac
}
