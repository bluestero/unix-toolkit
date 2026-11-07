# k-icon shell hook: tab completion. (k-icon itself is kitty/bin/k-icon.)

unset -f k-icon 2>/dev/null   # older toolkit versions defined it as a function
_k_icon_complete() {
  [ "$COMP_CWORD" -eq 1 ] || return 0
  COMPREPLY=($(compgen -W "ls current help $(command k-icon __names 2>/dev/null)" -- "${COMP_WORDS[1]}"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _k_icon_complete k-icon 2>/dev/null
