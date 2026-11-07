# k-theme shell hook: tab completion with the subcommands and the theme names
# that have no spaces (for the rest: quote them, or search in the picker).

_k_theme_complete() {
  [ "$COMP_CWORD" -eq 1 ] || return 0
  local own
  own=$(command k-theme __names 2>/dev/null | grep -v ' ')
  COMPREPLY=($(compgen -W "ls status current add rm default update help $own" -- "${COMP_WORDS[1]}"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _k_theme_complete k-theme 2>/dev/null
