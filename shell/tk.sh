# tk shell hook: lets the tk picker run the chosen command in this shell (so
# okcli and kx can still change this terminal), and adds tab completion.

unalias tk 2>/dev/null
tk() {
  local f rc
  f=$(mktemp "${TMPDIR:-/tmp}/tk.XXXXXX") || return 1
  TK_EVAL_FILE="$f" command tk "$@"
  rc=$?
  if [ -s "$f" ]; then
    # the picker writes one command name; run it here, as if you typed it
    local cmd; cmd=$(head -n1 "$f")
    rm -f "$f"
    case "$cmd" in *[!a-z-]*|"") return 1 ;; esac
    "$cmd"
    return
  fi
  rm -f "$f"
  return $rc
}

_tk_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" words
  if [ "$COMP_CWORD" -eq 1 ]; then words="ls status doctor install uninstall update help"
  else
    case "${COMP_WORDS[1]}" in
      install|uninstall) words="ls help --dry-run --details --yes --plain $(sed -n 's/^COMPONENTS=(\(.*\))$/\1/p' "$(dirname "$(command -v tk)")/../lib/components.sh" 2>/dev/null)" ;;
      *) words="" ;;
    esac
  fi
  COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _tk_complete tk 2>/dev/null
