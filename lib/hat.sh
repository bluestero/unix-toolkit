# Which hat a folder wears: its Claude profile, GitHub account and AWS profile.
# Sourced by hat and ws.
#
#   Claude   export CLAUDE_CONFIG_DIR=...   in the folder's .envrc (direnv)
#   AWS      export AWS_PROFILE=...         in the folder's .envrc (as okcli pin writes it)
#   GitHub   [includeIf "gitdir:<folder>/"] in ~/.gitconfig, pointing at an account
#            file ~/.config/hat/github/<account>.gitconfig (name, email, SSH key)
# Subfolders get the same hat: .envrc files hat writes start with source_up_if_exists,
# and gitdir: rules cover every repo below the folder.
#
#   hat_get <dir>            claude<TAB>github<TAB>aws: "name", "name<TAB>↑" style cells
#                            (see hat_cells), empty = the default
#   hat_claude_profiles      one profile name per line (~/.claude-profiles/*)
#   hat_github_accounts      one account per line
#   hat_aws_profiles         one profile per line

HAT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hat"
HAT_FOLDERS="$HAT_DIR/folders"
HAT_GH="$HAT_DIR/github"
HAT_CLAUDE="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"

hat_claude_profiles() { local d; for d in "$HAT_CLAUDE"/*/; do [[ -d $d ]] && basename "$d"; done; return 0; }
hat_github_accounts() { local f; for f in "$HAT_GH"/*.gitconfig; do [[ -f $f ]] && basename "$f" .gitconfig; done; return 0; }
hat_aws_profiles() {
  local f
  for f in "${AWS_CONFIG_FILE:-$HOME/.aws/config}" "${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"; do
    [[ -r $f ]] && sed -n 's/^\[\(profile \)\{0,1\}\([^]]*\)\].*/\2/p' "$f"
  done | grep -vx default | sort -u
  return 0
}
hat_gh_email() { git config -f "$HAT_GH/$1.gitconfig" user.email 2>/dev/null; }

# The value an .envrc gives VAR in <dir>: <value><TAB><folder it's set in>.
# direnv loads the nearest .envrc only, so the walk up goes on only through
# .envrc files that source their parents (source_up...).
hat_envrc_get() {
  local d=$1 var=$2 v
  while :; do
    if [[ -f $d/.envrc ]]; then
      v=$(sed -n "s/^export $var=\([^ ]*\).*/\1/p" "$d/.envrc" | tail -n1)
      if [[ -n $v ]]; then
        v=${v//\"/}; v=${v//\'/}; v=${v//\$\{HOME\}/$HOME}; v=${v//\$HOME/$HOME}; v=${v/#\~/$HOME}
        printf '%s\t%s\n' "$v" "$d"; return 0
      fi
      grep -q '^[[:space:]]*source_up' "$d/.envrc" || return 0
    fi
    [[ $d == / || -z $d ]] && return 0
    d=$(dirname "$d")
  done
}

# ~/.gitconfig's folder rules that hat made: <folder><TAB><account>
hat_git_rules() {
  git config --global --get-regexp '^includeif\.gitdir:.*\.path$' 2>/dev/null |
    while read -r k v; do
      [[ $v == */hat/github/*.gitconfig ]] || continue
      k=${k#includeif.gitdir:}; k=${k%.path}; k=${k%/}
      printf '%s\t%s\n' "${k/#\~/$HOME}" "$(basename "$v" .gitconfig)"
    done
}

# The GitHub account for <dir>: <account><TAB><where from: folder, or "remote">
hat_github_get() {
  local d=$1 f a best="" acct="" e x
  while IFS=$'\t' read -r f a; do
    [[ $d == "$f" || $d == "$f"/* ]] && (( ${#f} > ${#best} )) && { best=$f; acct=$a; }
  done < <(hat_git_rules)
  [[ -n $acct ]] && { printf '%s\t%s\n' "$acct" "$best"; return 0; }
  # no folder rule: a repo can still get an account from its remote (hasconfig rules)
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || return 0
  e=$(git -C "$d" config user.email 2>/dev/null)
  [[ -n $e && $e != "$(git config --global user.email)" ]] || return 0
  for x in $(hat_github_accounts); do
    [[ $(hat_gh_email "$x") == "$e" ]] && { printf '%s\tremote\n' "$x"; return 0; }
  done
  printf '%s\tremote\n' "$e"
}

# hat_get <dir>: claude<TAB>from<TAB>github<TAB>from<TAB>aws<TAB>from
# ("from" is the folder it's set in, or "remote"; empty value = the default)
hat_get() {
  local d c g a
  d=$(realpath -m -- "$1")
  c=$(hat_envrc_get "$d" CLAUDE_CONFIG_DIR)
  [[ -n $c ]] && c="$(basename "${c%%$'\t'*}")"$'\t'"${c#*$'\t'}"
  g=$(hat_github_get "$d")
  a=$(hat_envrc_get "$d" AWS_PROFILE)
  printf '%s\t%s\t%s\n' "${c:-$'\t'}" "${g:-$'\t'}" "${a:-$'\t'}"
}

# hat_cells <dir>: the three values for a table, coloured: name (set here),
# name ↑ (from a parent folder), name ⇄ (from the repo's remote), – (default)
hat_cells() {
  local d v f out=() i
  local -a x
  d=$(realpath -m -- "$1")
  IFS=$'\t' read -r -a x <<<"$(hat_get "$d" | sed 's/\t/\t·/g; s/^/·/')"
  for i in 0 2 4; do
    v=${x[i]#·}; f=${x[i+1]#·}
    if [[ -z $v ]]; then out+=("${C_DIM}–${C_RESET}")
    elif [[ $f == remote ]]; then out+=("$v ${C_DIM}⇄${C_RESET}")
    elif [[ $f == "$d" ]]; then out+=("$v")
    else out+=("$v ${C_DIM}↑${C_RESET}"); fi
  done
  local IFS=$'\x1f'; printf '%s' "${out[*]}"
}
