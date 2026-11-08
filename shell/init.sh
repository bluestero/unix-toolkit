# Work shell toolkit: the one file your shell loads. Works in bash and zsh.
#   bash: ~/.bashrc has one line that sources this (install.sh adds it)
#   zsh:  zsh/zshrc sources it
#
# Loads, in order: shared aliases/PATH/env (common.sh), the direnv and starship
# hooks, then the tools. Safe to source more than once.

_work_root="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
if [ -n "${ZSH_VERSION:-}" ]; then _work_sh=zsh; else _work_sh=bash; fi

case ":$PATH:" in *":$_work_root/bin:"*) ;; *) PATH="$_work_root/bin:$PATH" ;; esac
# Layers (lib/layers.sh): extra parts in layers/<name>/, each from its own repo.
# Listed with ls, not a glob: an empty glob is an error in zsh.
# (Loops use $(...) because zsh doesn't split a plain variable into words.)
_work_layers() { command ls -1 "$_work_root/layers" 2>/dev/null | sed 's|^|layers/|'; }
for _d in okta kube twingate ws kitty $(_work_layers); do
  case ":$PATH:" in *":$_work_root/$_d/bin:"*) ;; *) [ -d "$_work_root/$_d/bin" ] && PATH="$_work_root/$_d/bin:$PATH" ;; esac
done
export PATH

[ -r "$_work_root/shell/common.sh" ] && . "$_work_root/shell/common.sh"
# A layer's settings come before the tools, which read them (OKTA_AWSCLI_*, KX_ALIAS_RULES).
for _l in $(_work_layers); do
  [ -r "$_work_root/$_l/shell/init.sh" ] && . "$_work_root/$_l/shell/init.sh"
done

# direnv first, then starship, then the tools: okcli's prompt hook has to run
# after direnv has applied a repo pin.
# Quiet: no "direnv: loading / export" lines; the prompt already shows the AWS
# profile. Errors (a blocked .envrc) still show. Set DIRENV_LOG_FORMAT to get them back.
export DIRENV_LOG_FORMAT="${DIRENV_LOG_FORMAT-}"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook $_work_sh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init $_work_sh)"

# A blank line before each prompt, except the first one (and the first after
# 'clear'): a new terminal starts on the top line, not one down.
_work_gap() { [ -n "${_work_prompted:-}" ] && echo; _work_prompted=1; }
clear() { command clear "$@"; unset _work_prompted; }
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook && add-zsh-hook precmd _work_gap
elif declare -F starship_precmd >/dev/null; then
  case "${STARSHIP_PROMPT_COMMAND:-}" in *_work_gap*) ;; *)
    STARSHIP_PROMPT_COMMAND="_work_gap${STARSHIP_PROMPT_COMMAND:+;$STARSHIP_PROMPT_COMMAND}" ;; esac
else
  case "${PROMPT_COMMAND:-}" in *_work_gap*) ;; *)
    PROMPT_COMMAND="_work_gap${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;; esac
fi

for _f in \
  okta/shell/okta-env.sh \
  okta/shell/okcli.sh \
  kube/shell/kx.sh \
  twingate/shell/twin.sh \
  ws/shell/ws.sh \
  kitty/shell/k-config.sh \
  shell/tk.sh
do
  [ -r "$_work_root/$_f" ] && . "$_work_root/$_f"
done
unset _f _d _l _work_root _work_sh; unset -f _work_layers

# One name per tool (no okp / kctx); old shells may still have them, so drop them.
unalias okp kctx 2>/dev/null
