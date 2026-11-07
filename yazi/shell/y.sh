# y: open yazi, and leave the shell in the folder you quit in (q). Q quits without cd.
y() {
  local tmp cwd
  command -v yazi >/dev/null 2>&1 || { echo "y: yazi isn't installed (./install.sh yazi)" >&2; return 1; }
  tmp=$(mktemp -t yazi-cwd.XXXXXX)
  command yazi "$@" --cwd-file="$tmp"
  if cwd=$(command cat -- "$tmp") && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
