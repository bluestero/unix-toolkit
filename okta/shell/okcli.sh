# okcli shell hook - source this from ~/.bashrc or ~/.zshrc.
#
# Wraps the okcli binary so switching (okcli <profile>) can change AWS_PROFILE in the
# current shell, restores the last profile in new shells, and adds completion.

export OKCLI_SHELL=1

# A leftover 'alias okcli=...' would shadow the function below.
unalias okcli 2>/dev/null

okcli() {
  local f rc
  f=$(mktemp "${TMPDIR:-/tmp}/okcli.XXXXXX") || return 1
  OKCLI_EVAL_FILE="$f" command okcli "$@"
  rc=$?
  [ -s "$f" ] && . "$f"
  rm -f "$f"
  return $rc
}

# New shells start on the default ('okcli default <p>'). A repo pin (.envrc)
# still wins: direnv applies it on the first prompt.
_okcli_state="${XDG_CONFIG_HOME:-$HOME/.config}/okcli"
if [ -z "${AWS_PROFILE:-}" ]; then
  for _f in "$_okcli_state/default" "$_okcli_state/current"; do  # 'current' = pre-1.1 name
    if [ -r "$_f" ]; then AWS_PROFILE=$(head -n1 "$_f"); export AWS_PROFILE; break; fi
  done
  unset _f
fi

# For the prompt: exports the active profile as exactly one of
#   OKCLI_AWS (dev) · OKCLI_AWS_PROD · OKCLI_AWS_EXPIRED
# so starship can color it, plus the time its login has left as one of
#   OKCLI_AWS_LEFT ("2h34m") · OKCLI_AWS_LEFT_LOW (under 30 minutes).
# Runs every prompt, after direnv. Pure bash: it only calls okcli when
# okta.yaml or ~/.aws/credentials changed since the last time.
_okcli_precmd() {
  local p="${AWS_PROFILE:-}" yaml="${OKCLI_OKTA_YAML:-$HOME/.okta/okta.yaml}"
  local creds="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  local prodf="$_okcli_state/prod-profiles" expf="$_okcli_state/expiries" n t exp="" prod=0 left
  unset OKCLI_AWS OKCLI_AWS_PROD OKCLI_AWS_EXPIRED OKCLI_AWS_LEFT OKCLI_AWS_LEFT_LOW
  [ -n "$p" ] || return 0
  mkdir -p "$_okcli_state"
  if [ ! -f "$prodf" ] || [ "$yaml" -nt "$prodf" ]; then command okcli __prod_names >"$prodf" 2>/dev/null; fi
  if [ -r "$creds" ] && { [ ! -f "$expf" ] || [ "$creds" -nt "$expf" ]; }; then
    command okcli __expiries >"$expf" 2>/dev/null
  fi
  if [ -r "$prodf" ]; then while read -r n; do [ "$n" = "$p" ] && prod=1; done <"$prodf"; fi
  if [ -r "$expf" ]; then while read -r n t; do [ "$n" = "$p" ] && exp=$t; done <"$expf"; fi
  if [ -n "$exp" ] && [ -n "${EPOCHSECONDS:-}" ]; then
    left=$((exp - EPOCHSECONDS))
    if [ "$left" -le 0 ]; then export OKCLI_AWS_EXPIRED="$p"; return 0; fi
    if [ "$left" -ge 3600 ]; then t="$((left / 3600))h$((left % 3600 / 60))m"; else t="$((left / 60))m"; fi
    if [ "$left" -lt 1800 ]; then export OKCLI_AWS_LEFT_LOW="$t"; else export OKCLI_AWS_LEFT="$t"; fi
  fi
  if [ "$prod" = 1 ]; then export OKCLI_AWS_PROD="$p"
  else export OKCLI_AWS="$p"; fi
}
if [ -n "${ZSH_VERSION:-}" ]; then
  zmodload zsh/datetime 2>/dev/null   # EPOCHSECONDS, for the expiry check
  autoload -Uz add-zsh-hook && add-zsh-hook precmd _okcli_precmd   # no duplicates on re-source
elif declare -F starship_precmd >/dev/null; then
  # starship already took PROMPT_COMMAND; it evals this after its own hook.
  case "${STARSHIP_PROMPT_COMMAND:-}" in *_okcli_precmd*) ;; *)
    STARSHIP_PROMPT_COMMAND="${STARSHIP_PROMPT_COMMAND:+$STARSHIP_PROMPT_COMMAND;}_okcli_precmd" ;; esac
else
  case "${PROMPT_COMMAND:-}" in *_okcli_precmd*) ;; *)
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_okcli_precmd" ;; esac
fi

# Prompt segment for people without starship: PS1='$(_okcli_ps1)'"$PS1"
_okcli_ps1() {
  local p
  p=$(command okcli __ps1 2>/dev/null)
  [ -n "$p" ] || return 0
  case "$p" in
    *!) printf '\001\033[31m\002[%s expired]\001\033[0m\002 ' "${p%!}" ;;
    *)  printf '\001\033[36m\002[%s]\001\033[0m\002 ' "$p" ;;
  esac
}

_okcli_complete() {
  local cur prev cmds
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="ls status current off default refresh whoami exec pin unpin sync add rename remove edit env doctor help"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$cmds $(command okcli __names 2>/dev/null)" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      default) COMPREPLY=($(compgen -W "off $(command okcli __names 2>/dev/null)" -- "$cur")) ;;
      whoami|exec|pin|rename|remove|env)
        COMPREPLY=($(compgen -W "$(command okcli __names 2>/dev/null)" -- "$cur")) ;;
      refresh)
        COMPREPLY=($(compgen -W "--expired --current $(command okcli __names 2>/dev/null)" -- "$cur")) ;;
      help) COMPREPLY=($(compgen -W "setup" -- "$cur")) ;;
    esac
  elif [ "${COMP_WORDS[1]}" = refresh ]; then
    COMPREPLY=($(compgen -W "$(command okcli __names 2>/dev/null)" -- "$cur"))
  fi
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X bashcompinit 2>/dev/null && bashcompinit
fi
complete -F _okcli_complete okcli 2>/dev/null
