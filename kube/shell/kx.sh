# kx shell hook - source from ~/.bashrc or ~/.zshrc (shell/init.sh does it).
#
# Gives each shell its own kubeconfig overlay file, wraps kx so it can change
# KUBECONFIG here, cleans the overlay up on exit, and adds completion.

export KX_SHELL=1

# The real kubeconfig(s), remembered before any overlay goes in front.
if [ -z "${KX_BASE_KUBECONFIG:-}" ]; then
  if [ -n "${KUBECONFIG:-}" ]; then export KX_BASE_WAS_SET=1; fi
  export KX_BASE_KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
fi

_kx_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/kx-${UID:-$(id -u)}"
_kx_parent_file="${KX_SHELL_FILE:-}"
export KX_SHELL_FILE="$_kx_dir/shell-$$.yaml"

# A nested shell inherits its parent's context: copy the parent's overlay so
# it survives the parent exiting.
if [ -n "$_kx_parent_file" ] && [ "$_kx_parent_file" != "$KX_SHELL_FILE" ] && [ -f "$_kx_parent_file" ]; then
  mkdir -p "$_kx_dir" && chmod 700 "$_kx_dir" && cp -p "$_kx_parent_file" "$KX_SHELL_FILE" &&
    export KUBECONFIG="$KX_SHELL_FILE:$KX_BASE_KUBECONFIG"
fi
unset _kx_parent_file

_kx_cleanup() { [ -n "${KX_SHELL_FILE:-}" ] && rm -f "$KX_SHELL_FILE"; }
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook && add-zsh-hook zshexit _kx_cleanup
else
  # Keep any EXIT trap that's already there.
  _kx_trap=$(trap -p EXIT | sed -n "s/^trap -- '\(.*\)' EXIT\$/\1/p")
  case "$_kx_trap" in *_kx_cleanup*) ;; *) trap "_kx_cleanup${_kx_trap:+; $_kx_trap}" EXIT ;; esac
  unset _kx_trap
fi

unalias kx 2>/dev/null
kx() {
  local f rc
  f=$(mktemp "${TMPDIR:-/tmp}/kx.XXXXXX") || return 1
  KX_EVAL_FILE="$f" command kx "$@"
  rc=$?
  [ -s "$f" ] && . "$f"
  rm -f "$f"
  return $rc
}

_kx_complete() {
  local cur prev cmds
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="ls status current ns off default exec pods why logs shell deploys restart configs secrets services forward events top get changes sync ignore unignore rm tidy link unlink rename doctor help"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$cmds $(command kx __names 2>/dev/null)" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      default|link|unlink|rename|exec|rm|ignore)
        COMPREPLY=($(compgen -W "$(command kx __names 2>/dev/null)" -- "$cur")) ;;
      logs|shell|forward|why)
        COMPREPLY=($(compgen -W "$(timeout 3 kubectl get pods -o name 2>/dev/null | sed 's|^pod/||')" -- "$cur")) ;;
      restart)
        COMPREPLY=($(compgen -W "$(timeout 3 kubectl get deployments -o name 2>/dev/null | sed 's|^deployment.apps/||')" -- "$cur")) ;;
      top) COMPREPLY=($(compgen -W "pods nodes" -- "$cur")) ;;
      get) COMPREPLY=($(compgen -W "$(timeout 3 kubectl api-resources --verbs=list -o name 2>/dev/null | sed 's/\..*//')" -- "$cur")) ;;
      unignore) COMPREPLY=($(compgen -W "$(sed 's/#.*//' "${XDG_CONFIG_HOME:-$HOME/.config}/kx/ignore" 2>/dev/null | awk 'NF { print $1 }')" -- "$cur")) ;;
      sync) COMPREPLY=($(compgen -W "$(command okcli __names 2>/dev/null)" -- "$cur")) ;;
    esac
  elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[1]}" = link ]; then
    COMPREPLY=($(compgen -W "$(command okcli __names 2>/dev/null)" -- "$cur"))
  fi
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _kx_complete kx 2>/dev/null
