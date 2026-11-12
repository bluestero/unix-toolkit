# Tab completion for every toolkit and layer command that has no completer of its
# own (okcli, kx, twin, ws, tk and k-theme have theirs). The first word comes from
# the command's help page (the lines "<cmd> <word> ..."), so it never falls behind.
# A command adds the words that come later with a function _work_complete_<cmd>
# (- as _): it reads COMP_WORDS / COMP_CWORD and prints one word per line (spaces
# allowed). Loaded last by shell/init.sh; a layer's commands come from its tools file.

_work_complete() {
  local cmd="${COMP_WORDS[0]##*/}" cur="${COMP_WORDS[COMP_CWORD]}" words="" fn w
  [ "$COMP_CWORD" -eq 1 ] &&
    words=$(command "$cmd" help 2>/dev/null </dev/null | sed -n "s/^ *$cmd \([a-z][a-z-]*\).*/\1/p")
  fn="_work_complete_$(printf '%s' "$cmd" | tr - _)"
  if type "$fn" >/dev/null 2>&1; then words="$words
$("$fn" 2>/dev/null)"; fi
  cur=$(printf '%s' "$cur" | sed 's/\\//g')   # what's typed, escapes taken out ("Media\ A")
  COMPREPLY=()
  while IFS= read -r w; do   # the words that start with it, once each, spaces escaped
    [ -n "$w" ] && case "$w" in "$cur"*) case " ${COMPREPLY[*]} " in *" $(printf '%q' "$w") "*) ;; *) COMPREPLY+=("$(printf '%q' "$w")") ;; esac ;; esac
  done <<EOF
$words
EOF
}

# hat: the second word of claude / github, then the profile or account
_work_complete_hat() {
  local d
  case "$COMP_CWORD:${COMP_WORDS[1]}" in
    2:claude) printf '%s\n' add rm ;;
    2:github) printf '%s\n' add rm login ;;
    3:claude) [ "${COMP_WORDS[2]}" = rm ] && command ls -1 "${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}" ;;
    3:github)
      case "${COMP_WORDS[2]}" in rm|login)
        for d in "${XDG_CONFIG_HOME:-$HOME/.config}"/hat/github/*.gitconfig; do
          [ -f "$d" ] && { d=${d##*/}; printf '%s\n' "${d%.gitconfig}"; }
        done ;;
      esac ;;
  esac
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
for _c in ctx hat k-config $(sed -n 's/^\([a-z][a-z0-9-]*\)|.*/\1/p' "$_work_root"/layers/*/tools 2>/dev/null); do
  if [ -n "${ZSH_VERSION:-}" ]; then
    (( ${+_comps[$_c]} )) && continue
  else
    complete -p "$_c" >/dev/null 2>&1 && continue
  fi
  # hat show/set/off take a folder: with no word of ours, the shell completes paths
  if [ "$_c" = hat ]; then complete -o default -F _work_complete "$_c" 2>/dev/null
  else complete -F _work_complete "$_c" 2>/dev/null; fi
done
unset _c
