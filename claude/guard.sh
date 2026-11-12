#!/usr/bin/env bash
# guard - Claude Code's PreToolUse hook for Bash (runs as `tk __guard`; the
# claude-guard part of the installer adds it). Reads the tool call (JSON on stdin)
# and has the user approve a command first when it:
#   - changes something on a PROD AWS profile or Kubernetes context it names, or
#   - runs aws / kubectl / helm / terraform without naming a target while the
#     inherited profile or context is PROD.
# It notes a session with under 15 minutes left (or expired). Anything else: no
# output, so Claude Code's normal permission flow is unchanged. It reads the
# command's words, so it's a safety net for the usual forms, not a full parser.

set -uo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"
# shellcheck source=../lib/hat.sh
. "$ROOT/lib/hat.sh"

{ IFS= read -r cwd; cmd=$(cat); } < <(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("cwd", "")); print((d.get("tool_input") or {}).get("command", ""))')
[[ $cmd =~ (^|[^[:alnum:]_-])(aws|kubectl|helm|terraform|eksctl|okcli|kx|hat|direnv)([^[:alnum:]_-]|$) ]] || exit 0
cwd=${cwd:-$PWD}

# The command's words, shell punctuation turned into ";" words. A tool counts only
# where a command starts (a segment's first word, after "--" or a wrapper like
# okcli exec <profile>), so "grep aws" isn't aws; a verb that changes things
# counts only in a segment that runs a cloud tool.
read -r -a w <<<"$(sed 's/[;|&()`]/ ; /g; s/\$(/ ; /g' <<<"$cmd")"
CHANGES='^(create|delete|put|update|modify|terminate|start|stop|reboot|attach|detach|associate|disassociate|remove|add|tag|untag|invoke|publish|send|set|restore|register|deregister|enable|disable|import|reset|revoke|authorize|cancel|execute|run|replace|copy|purge|rotate)(-|$)|^(cp|mv|rm|sync|mb|rb|apply|edit|patch|scale|rollout|label|annotate|drain|cordon|uncordon|taint|untaint|exec|autoscale|expose|debug|install|upgrade|uninstall|rollback|destroy|state|restart|shell|secrets|forward)$'
profiles=() contexts=() aws_tool=0 kube_tool=0 changes=0 pinned=0 start=1 tool=0
for ((i = 0; i < ${#w[@]}; i++)); do
  x=${w[i]} n=${w[i+1]:-}
  case $x in
    ";") start=1 tool=0; continue ;;
    --) start=1; continue ;;
    --profile) profiles+=("$n") ;;
    --profile=*) profiles+=("${x#*=}") ;;
    AWS_PROFILE=*) profiles+=("${x#*=}") ;;
    --context|--kube-context) contexts+=("$n") ;;
    --context=*|--kube-context=*) contexts+=("${x#*=}") ;;
  esac
  if (( start )); then
    case $x in
      *=*|sudo|env|time|nohup|command|xargs|watch) continue ;;   # still before the command
    esac
    start=0
    if [[ $n == exec ]]; then   # okcli/kx/hat/direnv exec: note the target, go on to its command
      case $x in
        okcli) profiles+=("${w[i+2]:-}"); i=$((i + 2)); start=1; continue ;;
        kx) contexts+=("${w[i+2]:-}"); i=$((i + 2)); start=1; continue ;;
        hat|direnv)   # the folder's pin
          IFS=$'\t' read -r p _ <<<"$(hat_envrc_get "$(realpath -m -- "$cwd")" AWS_PROFILE)"
          [[ -n ${p:-} ]] && { profiles+=("$p"); pinned=1; }
          i=$((i + 1)); [[ $x == direnv ]] && i=$((i + 1)); start=1; continue ;;
      esac
    fi
    case $x in
      aws|terraform|eksctl) aws_tool=1 tool=1 ;;
      kubectl|helm|kx) kube_tool=1 tool=1 ;;
    esac
    continue
  fi
  (( tool )) && [[ $x =~ $CHANGES ]] && changes=1
done

prod_names=$'\n'"$(okcli __prod_names 2>/dev/null)"$'\n'
prod_profile() { [[ $prod_names == *$'\n'"$1"$'\n'* ]]; }
describe() {   # profile -> "name (account, role)"
  local a r; IFS=$'\t' read -r _ _ a r _ < <(okcli __profiles 2>/dev/null | awk -F'\t' -v p="$1" '$1 == p')
  printf '%s%s' "$1" "${a:+ ($a${r:+, role $r})}"
}
ask=() note=()
for p in "${profiles[@]}"; do
  [[ -n $p ]] && (( changes )) && prod_profile "$p" && ask+=("it changes something on the PROD AWS profile $(describe "$p")")
done
for c in "${contexts[@]}"; do
  [[ -n $c ]] && (( changes )) && is_prod "$c" && ask+=("it changes something on the PROD Kubernetes context $c")
done
# no target named: the one inherited from the terminal Claude started in
if (( aws_tool && ${#profiles[@]} == 0 && ! pinned )) && [[ -n ${AWS_PROFILE:-} ]]; then
  profiles+=("$AWS_PROFILE")
  prod_profile "$AWS_PROFILE" && ask+=("it uses the inherited AWS profile $(describe "$AWS_PROFILE"), which is PROD, without naming one (okcli exec <profile> -- ...)")
fi
if (( kube_tool && ${#contexts[@]} == 0 )); then
  k=$(kubectl config current-context 2>/dev/null)
  [[ -n $k ]] && is_prod "$k" && ask+=("it uses the inherited Kubernetes context $k, which is PROD, without naming one (kx exec <context> -- ...)")
fi

# sessions about to run out
now=$(date +%s)
while read -r p e; do
  for q in "${profiles[@]}"; do
    [[ $q == "$p" ]] || continue
    left=$(( e - now ))
    if (( left <= 0 )); then note+=("the AWS session for $p has expired: ask the user to run okcli refresh $p")
    elif (( left < 900 )); then note+=("the AWS session for $p has $(( left / 60 ))m left: before a long task, ask the user to run okcli refresh $p"); fi
  done
done < <(okcli __expiries 2>/dev/null)

(( ${#ask[@]} + ${#note[@]} )) || exit 0
python3 -I - "$(printf '%s\n' "${ask[@]}")" "$(printf '%s\n' "${note[@]}")" <<'PY'
import json, sys
ask, note = ([l for l in a.splitlines() if l] for a in sys.argv[1:])
out = {"hookEventName": "PreToolUse"}
if ask:   # the reason shows in the user's prompt; the context tells Claude why
    out["permissionDecision"] = "ask"
    out["permissionDecisionReason"] = "work-toolkit guard: " + "; ".join(ask + note)
out["additionalContext"] = "work-toolkit guard: " + "; ".join(ask + note)
print(json.dumps({"hookSpecificOutput": out}))
PY
