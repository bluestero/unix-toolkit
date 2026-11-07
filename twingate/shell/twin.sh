# twin shell hook: tab completion.

_twin_complete() {
  [ "$COMP_CWORD" -eq 1 ] || return 0
  COMPREPLY=($(compgen -W "ls status current off help $(command twin __codes 2>/dev/null)" -- "${COMP_WORDS[1]}"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _twin_complete twin 2>/dev/null
