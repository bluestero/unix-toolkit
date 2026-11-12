# For the prompt: HAT_GH, the GitHub account git uses in this repo, only when it isn't
# your default one (the repo's email differs from the global one): hat's rule for the
# folder, else the hat account with that email, else the email itself.
# Runs every prompt, after direnv: one git call outside a repo.
_hat_precmd() {
  local e s f l
  unset HAT_GH
  command git rev-parse --git-dir >/dev/null 2>&1 || return 0
  e=$(command git config --get user.email 2>/dev/null)
  [ "$e" = "$(command git config --global --get user.email 2>/dev/null)" ] && return 0
  s=$(command git config --get core.sshCommand 2>/dev/null)
  case "$s" in */hat/github/*.ssh_config*) s=${s##*/hat/github/}; export HAT_GH="${s%%.ssh_config*}"; return 0 ;; esac
  [ -n "$e" ] || return 0
  [ -n "${ZSH_VERSION:-}" ] && setopt localoptions nullglob
  for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/hat/github/*.gitconfig; do
    while read -r l; do
      case "$l" in "email = $e") s=${f##*/}; export HAT_GH="${s%.gitconfig}"; return 0 ;; esac
    done <"$f"
  done
  export HAT_GH="$e"
}
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook && add-zsh-hook precmd _hat_precmd
elif declare -F starship_precmd >/dev/null; then
  case "${STARSHIP_PROMPT_COMMAND:-}" in *_hat_precmd*) ;; *)
    STARSHIP_PROMPT_COMMAND="${STARSHIP_PROMPT_COMMAND:+$STARSHIP_PROMPT_COMMAND;}_hat_precmd" ;; esac
else
  case "${PROMPT_COMMAND:-}" in *_hat_precmd*) ;; *)
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_hat_precmd" ;; esac
fi
