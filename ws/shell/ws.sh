# ws shell hook: tab completion for subcommands, workspace names and IDEs.

_ws_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" words
  case "$COMP_CWORD:${COMP_WORDS[1]:-}:${COMP_WORDS[2]:-}" in
    1:*)           words="ls close default edit help $(command ws __names 2>/dev/null)" ;;
    2:default:*)   words="$(command ws __ides 2>/dev/null)" ;;
    *:default:*)   words="" ;;
    *)             words="$(command ws __names 2>/dev/null)" ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _ws_complete ws 2>/dev/null
