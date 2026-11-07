# Personal aliases, PATH and env shared by bash and zsh (shell/init.sh loads it).
# Moved out of ~/.bashrc by install.sh so both shells get the same setup.

_work_path_prepend() {
  case ":$PATH:" in *":$1:"*) ;; *) [ -d "$1" ] && PATH="$1:$PATH" ;; esac
}
_work_path_prepend "$HOME/bin"
_work_path_prepend "$HOME/.local/bin"
export PATH
unset -f _work_path_prepend

# Aliases: only ones you don't have yet. Yours (from ~/.bashrc, ~/.zshrc, ...)
# always win, so installing the toolkit never changes what your own alias does,
# and uninstalling it can't lose one.
_work_alias() { alias "$1" >/dev/null 2>&1 || alias "$1=$2"; }

# ls / grep
_work_alias ls 'ls --color=auto'
_work_alias grep 'grep --color=auto'
_work_alias ll 'ls -alF'
_work_alias la 'ls -A'
_work_alias l 'ls -CF'

# Long-running commands: sleep 10; alert
_work_alias alert 'notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

_work_alias venv 'source env/bin/activate'
_work_alias gcb 'git branch | grep -v "^\*" | grep -v "master" | xargs git branch -D'
_work_alias pyclean 'find . -path "./env" -prune -o -type d -name "__pycache__" -exec rm -rf {} +'

# Edit / view this shell's rc file
_work_alias nb 'nano ~/.${ZSH_VERSION:+z}${BASH_VERSION:+ba}shrc'
_work_alias lb 'less ~/.${ZSH_VERSION:+z}${BASH_VERSION:+ba}shrc'
_work_alias cb 'cat ~/.${ZSH_VERSION:+z}${BASH_VERSION:+ba}shrc'

unset -f _work_alias

# Shell into a container (default: one named after this folder). Skipped if you
# have your own dex.
if ! type dex >/dev/null 2>&1 || [ -n "${_work_dex:-}" ]; then
  _work_dex=1
  dex() {
    local container_name="${1:-$(basename "$(pwd)")}"
    docker exec -it "$container_name" /bin/bash
  }
fi

# nvm, loaded lazily: sourcing nvm.sh costs ~0.8s per new terminal. The default
# node's bin goes straight on PATH (node/npm/npx work at once); the real nvm
# loads the first time you type `nvm`. If the default can't be resolved
# (e.g. an alias like lts/*), fall back to loading nvm normally.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  _nvm_def=$(cat "$NVM_DIR/alias/default" 2>/dev/null)
  _nvm_def=${_nvm_def#v}
  _nvm_bin=""
  [ -n "$_nvm_def" ] && _nvm_bin=$(find "$NVM_DIR/versions/node" -mindepth 1 -maxdepth 1 \
    \( -name "v$_nvm_def" -o -name "v$_nvm_def.*" \) 2>/dev/null | sort -V | tail -n1)
  if [ -n "$_nvm_bin" ] && [ -x "$_nvm_bin/bin/node" ]; then
    case ":$PATH:" in *":$_nvm_bin/bin:"*) ;; *) export PATH="$_nvm_bin/bin:$PATH" ;; esac
    nvm() {
      unset -f nvm
      . "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
      nvm "$@"
    }
  else
    . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
  fi
  unset _nvm_def _nvm_bin
fi
