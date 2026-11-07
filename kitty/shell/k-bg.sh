# k-bg shell hook: tab completion with the background names (also stops zsh
# suggesting file names after "k-bg ").

_k_bg_complete() {
  if [ "$COMP_CWORD" -eq 2 ] && [ "${COMP_WORDS[1]}" = accents ]; then
    COMPREPLY=($(compgen -W "on off" -- "${COMP_WORDS[2]}")); return 0
  fi
  [ "$COMP_CWORD" -eq 1 ] || return 0
  COMPREPLY=($(compgen -W "ls status current off bright opacity accents help none $(command k-bg __names 2>/dev/null)" -- "${COMP_WORDS[1]}"))
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _k_bg_complete k-bg 2>/dev/null
