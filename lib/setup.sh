# Plumbing shared by install.sh and uninstall.sh. Sourced, not executed.
#
# Expects: repo, mode (ask|yes|dry), details (0|1)
# Every helper checks the current state first and does nothing when it's
# already right, so running install/uninstall twice gives the same result.

ts=$(date +%Y%m%d-%H%M%S)
log_dir="$HOME/.local/state/work-toolkit"
log_file="$log_dir/setup.log"
mkdir -p "$log_dir"

# Colours and boxes come from lib/ui.sh, the same look as every toolkit command.
# The installer writes to stdout, so colour follows stdout (not stderr like the tools).
# shellcheck source=ui.sh
. "$repo/lib/ui.sh"
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then ui_color; else ui_no_color; fi
B=$C_BOLD D=$C_DIM G=$C_GREEN Y=$C_YELLOW Rd=$C_RED C=$C_CYAN R=$C_RESET
# (ok / warn below replace lib/ui.sh's: installer lines are indented and logged)

logf() { printf '%s\n' "$*" >>"$log_file"; }
say()  { printf '%s\n' "$*"; printf '%s\n' "$*" | sed 's/\x1b\[[0-9;]*m//g' >>"$log_file"; }
ok()   { say "${ok_pad-      }${G}✓${R} $*"; }
skip() { say "${ok_pad-      }${D}– skipped${R}${1:+ ($1)}"; }
warn() { say "      ${Y}!${R} $*"; }
fail() { say "      ${Rd}✗${R} $*"; }
dry()  { [[ "$mode" == dry ]]; }

# ask "<question>" [default y|n] → 0 = go ahead
ask() {
  local q="$1" def="${2:-y}" reply hint rc
  case "$mode" in
    dry) say "  ${C}?${R} $q ${D}(dry run: not asked)${R}"; return 1 ;;
    yes) say "  ${C}?${R} $q ${D}yes (--yes)${R}"; return 0 ;;
  esac
  if [[ -n "${GUM:-}" ]]; then
    "$GUM" confirm "$(printf '%s' "$q" | sed 's/\x1b\[[0-9;]*m//g')" \
      --default="$([[ "$def" == y ]] && echo true || echo false)" --no-show-help </dev/tty >/dev/tty
    rc=$?
    (( rc == 130 )) && { say ""; say "Stopped. What's done so far stays; run it again to carry on."; exit 130; }
    say "  ${C}?${R} $q ${D}$( (( rc )) && echo no || echo yes)${R}"
    return "$rc"
  fi
  if [[ "$def" == y ]]; then hint="[Y/n, default: yes]"; else hint="[y/N, default: no]"; fi
  read -r -p "  ${C}?${R} $q ${D}$hint${R} " reply </dev/tty
  logf "  ? $q -> ${reply:-default ($def)}"
  reply="${reply:-$def}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ask_text "<question>" "<prefill>" → ANSWER (1 = cancelled). --yes and dry runs
# take the prefill without asking.
ask_text() {
  local q="$1" def="$2"
  ANSWER=$def
  case "$mode" in
    dry) say "  ${C}?${R} $q ${D}$def (dry run: not asked)${R}"; return 0 ;;
    yes) say "  ${C}?${R} $q ${D}$def (--yes)${R}"; return 0 ;;
  esac
  ANSWER=$(ui_ask "$q" "$def") || return 1
  say "  ${C}?${R} $q ${D}${ANSWER}${R}"
}

# ---------------------------------------------------------------- gum ---
# gum (github.com/charmbracelet/gum) gives the checklist and the questions a
# nicer look. It's optional: without it the built-in plain versions are used.
# --plain (or WORK_TOOLKIT_PLAIN=1) never uses it.

GUM_VERSION=2.0.2
GUM=""

# use_gum: sets GUM to a gum that's new enough (has --label-delimiter). 0 = found.
use_gum() {
  local g
  GUM=""
  [[ "${WORK_TOOLKIT_PLAIN:-0}" == 1 || ! -t 0 || ! -t 1 ]] && return 1
  for g in "$(command -v gum 2>/dev/null)" "$HOME/.local/bin/gum"; do
    [[ -n "$g" && -x "$g" ]] || continue
    "$g" choose --help 2>&1 | grep -q -- '--label-delimiter' && { GUM=$g; return 0; }
  done
  return 1
}

# install_gum: download the gum release for this machine into ~/.local/bin
# (no sudo), after checking it against the release's checksums.txt.
install_gum() {
  local arch f url tmp sum bin
  case "$(uname -m)" in
    x86_64|amd64)  arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) warn "no gum download for $(uname -m)"; return 1 ;;
  esac
  command -v curl >/dev/null || { warn "curl is needed to download gum"; return 1; }
  f="gum_${GUM_VERSION}_Linux_${arch}.tar.gz"
  url="https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION"
  tmp=$(mktemp -d)
  if ! curl -fsSL --retry 2 -o "$tmp/$f" "$url/$f" 2>>"$log_file" ||
     ! curl -fsSL --retry 2 -o "$tmp/checksums.txt" "$url/checksums.txt" 2>>"$log_file"; then
    warn "couldn't download gum (offline?)"; rm -rf "$tmp"; return 1
  fi
  sum=$(awk -v f="$f" '$2 == f { print $1 }' "$tmp/checksums.txt")
  if [[ -z "$sum" || "$(sha256sum "$tmp/$f" | cut -d' ' -f1)" != "$sum" ]]; then
    warn "gum download didn't match its checksum, so it wasn't installed"; rm -rf "$tmp"; return 1
  fi
  tar xzf "$tmp/$f" -C "$tmp" 2>>"$log_file"
  bin=$(find "$tmp" -type f -name gum | head -1)
  [[ -n "$bin" ]] || { warn "no gum binary in the download"; rm -rf "$tmp"; return 1; }
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$bin" "$HOME/.local/bin/gum"
  rm -rf "$tmp"
  logf "gum $GUM_VERSION installed to ~/.local/bin/gum"
}

# ---------------------------------------------------------------- fzf ---
# Every picker uses fzf. Ubuntu's is old (0.44): no position counter, no
# Mine / All tabs in k-theme. fetch_fzf puts the release below in ~/.local/bin (no
# sudo, checked against its checksums file), ahead of apt's on PATH.
FZF_VERSION=0.74.5
FZF_MIN=0.60   # the position counter and k-theme's tabs need
fetch_fzf() {
  local arch f url tmp sum
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) warn "no fzf download for $(uname -m)"; return 1 ;;
  esac
  f="fzf-${FZF_VERSION}-linux_${arch}.tar.gz"
  url="https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION"
  tmp=$(mktemp -d)
  if ! curl -fsSL --retry 2 -o "$tmp/$f" "$url/$f" 2>>"$log_file" ||
     ! curl -fsSL --retry 2 -o "$tmp/sums" "$url/fzf_${FZF_VERSION}_checksums.txt" 2>>"$log_file"; then
    warn "couldn't download fzf (offline?)"; rm -rf "$tmp"; return 1
  fi
  sum=$(awk -v f="$f" '$2 == f { print $1 }' "$tmp/sums")
  if [[ -z "$sum" || "$(sha256sum "$tmp/$f" | cut -d' ' -f1)" != "$sum" ]]; then
    warn "fzf download didn't match its checksum, so it wasn't installed"; rm -rf "$tmp"; return 1
  fi
  tar xzf "$tmp/$f" -C "$tmp" fzf 2>>"$log_file" || { warn "no fzf in the download"; rm -rf "$tmp"; return 1; }
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/fzf" "$HOME/.local/bin/fzf"
  rm -rf "$tmp"
  logf "fzf $FZF_VERSION installed to ~/.local/bin/fzf"
  unset _UI_FZF_VER
}

# --------------------------------------------------------------- yazi ---
# Terminal file manager. The release below goes in ~/.local/bin (no sudo). The
# release has no checksums file, so the sha256 of each build is pinned here
# (GitHub's own digest of the asset); bump both together.
YAZI_VERSION=26.9.1
YAZI_SHA_x86_64=9b9c39decccf8cb0ff53a7d637d38f8a79d93bbd0099f4ea9c619ef6bb392f5d
YAZI_SHA_aarch64=dd569daecaae914185f295634109295ccd25c1b42b02eb89a74f651970024f2e
fetch_yazi() {
  local arch f url tmp sum want
  case "$(uname -m)" in
    x86_64|amd64)  arch=x86_64;  want=$YAZI_SHA_x86_64 ;;
    aarch64|arm64) arch=aarch64; want=$YAZI_SHA_aarch64 ;;
    *) warn "no yazi download for $(uname -m)"; return 1 ;;
  esac
  command -v unzip >/dev/null || { warn "unzip is needed to unpack yazi"; return 1; }
  f="yazi-${arch}-unknown-linux-musl.zip"
  url="https://github.com/sxyazi/yazi/releases/download/v$YAZI_VERSION/$f"
  tmp=$(mktemp -d)
  curl -fsSL --retry 2 -o "$tmp/$f" "$url" 2>>"$log_file" || { warn "couldn't download yazi (offline?)"; rm -rf "$tmp"; return 1; }
  sum=$(sha256sum "$tmp/$f" | cut -d' ' -f1)
  [[ "$sum" == "$want" ]] || { warn "yazi download didn't match its checksum, so it wasn't installed"; rm -rf "$tmp"; return 1; }
  unzip -qo -j "$tmp/$f" '*/yazi' '*/ya' -d "$tmp/out" 2>>"$log_file" || { warn "no yazi in the download"; rm -rf "$tmp"; return 1; }
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/out/yazi" "$HOME/.local/bin/yazi"
  install -m 755 "$tmp/out/ya" "$HOME/.local/bin/ya"
  rm -rf "$tmp"
  logf "yazi $YAZI_VERSION installed to ~/.local/bin"
}

# ------------------------------------------------- latest downloads ---
# The tools okcli, kx and the prompt run on (okta-aws-cli, kubectl, direnv,
# starship) come as the newest release for this CPU, into ~/.local/bin (no sudo).
# dl_arch: amd64 | arm64 (nothing on other CPUs)
dl_arch() { case "$(uname -m)" in x86_64|amd64) echo amd64 ;; aarch64|arm64) echo arm64 ;; esac; }
# gh_latest <owner/repo> <asset name, {v} = version>: sets GH_VER GH_URL GH_SHA
# from the newest GitHub release (GH_SHA = GitHub's sha256 of the asset). 1 = offline / no such asset.
gh_latest() {
  local out
  GH_VER="" GH_URL="" GH_SHA=""
  out=$(curl -fsS -m 10 "https://api.github.com/repos/$1/releases/latest" 2>>"$log_file" |
    python3 -Ic '
import json, sys
r = json.load(sys.stdin); v = r["tag_name"].lstrip("v"); want = sys.argv[1].replace("{v}", v)
for a in r["assets"]:
    if a["name"] == want and a.get("digest", "").startswith("sha256:"):
        print(v, a["browser_download_url"], a["digest"][7:])
' "$2" 2>>"$log_file") || return 1
  read -r GH_VER GH_URL GH_SHA <<<"$out"
  [[ -n $GH_URL ]]
}
# fetch_checked <url> <sha256> <file>: downloads it, keeps it only when the sha256 matches
fetch_checked() {
  curl -fsSL --retry 2 -o "$3" "$1" 2>>"$log_file" || { warn "couldn't download ${1##*/} (offline?)"; return 1; }
  [[ "$(sha256sum "$3" | cut -d' ' -f1)" == "$2" ]] && return 0
  warn "${1##*/} didn't match its checksum, so it wasn't installed"; rm -f "$3"; return 1
}

# --------------------------------------------------------------- files ---

# ------------------------------------------------------------ originals ---
# What you had before the toolkit, kept once and never overwritten, so uninstall
# can put your own setup back (not kitty's or Ubuntu's defaults):
#   originals/files/<path>   a file the first time install.sh changed it
#   originals/settings       key=value: a setting before install.sh first changed it
# Only install.sh adds to it (setup_phase=install); uninstall.sh only reads it.
orig_dir="$log_dir/originals"
orig_path() { local p=${1/#$HOME\//}; printf '%s/files/%s' "$orig_dir" "${p//\//%}"; }
keep_original() {
  [[ "${setup_phase:-}" == install && -f "$1" && ! -L "$1" ]] || return 0
  local o; o=$(orig_path "$1")
  [[ -e "$o" ]] && return 0
  mkdir -p "${o%/*}" && cp -p "$1" "$o" && logf "original kept: $1 -> $o"
}
# original_of <file>: your copy from before the toolkit; else the oldest backup (older installs)
original_of() {
  local o; o=$(orig_path "$1")
  if [[ -f "$o" ]]; then printf '%s' "$o"; else ls -1tr "$1".bak-* 2>/dev/null | head -1; fi
}
remember_setting() {   # remember_setting <key> <value>: only the first time
  [[ "${setup_phase:-}" == install ]] || return 0
  mkdir -p "$orig_dir"
  grep -q "^$1=" "$orig_dir/settings" 2>/dev/null || printf '%s=%s\n' "$1" "$2" >>"$orig_dir/settings"
}
recall_setting() { sed -n "s/^$1=//p" "$orig_dir/settings" 2>/dev/null | head -1; }
forget_setting() { [[ -f "$orig_dir/settings" ]] && sed -i "/^$1=/d" "$orig_dir/settings"; return 0; }

# backup <file>: copy a real file (not a link) to <file>.bak-<time>. Prints the name.
backup() {
  [[ -f "$1" && ! -L "$1" ]] || return 0
  keep_original "$1"
  cp -p "$1" "$1.bak-$ts" && printf '%s' "$1.bak-$ts"
}

# latest_backup <file>: newest <file>.bak-* (empty if none)
latest_backup() {
  local f newest=""
  for f in "$1".bak-*; do
    [[ -f "$f" ]] || continue
    [[ -z "$newest" || "$f" -nt "$newest" ]] && newest=$f
  done
  printf '%s' "$newest"
}

# linked <link> <target>: is <link> a symlink that resolves to <target>?
linked() { [[ -L "$1" && "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]; }

# link_file <link> <target>: point <link> at <target>, backing up a real file first.
link_file() {
  local link="$1" target="$2" b=""
  linked "$link" "$target" && return 0
  mkdir -p "$(dirname "$link")"
  [[ -f "$link" && ! -L "$link" ]] && b=$(backup "$link")
  ln -sfn "$target" "$link" || return 1
  logf "link $link -> $target${b:+ (backup: $b)}"
  ok "linked${b:+ (old file kept as ${b/#$HOME/\~})}"
}

# unlink_file <link> <target>: remove <link> if it points at <target>, and put
# back the newest backup if there is one.
unlink_file() {
  local link="$1" target="$2" b
  linked "$link" "$target" || return 0
  rm -f "$link"
  b=$(latest_backup "$link")
  if [[ -n "$b" ]]; then mv "$b" "$link"; ok "removed, put back ${b/#$HOME/\~}"
  elif b=$(orig_path "$link") && [[ -f "$b" ]]; then cp -p "$b" "$link"; ok "removed, put back your original"
  else ok "removed"; fi
}

# ------------------------------------------------- managed rc blocks ---
# A block looks like:
#   # >>> work toolkit >>>
#   ...
#   # <<< work toolkit <<<

BLOCK_START="# >>> work toolkit >>>"
BLOCK_END="# <<< work toolkit <<<"

# has_block <file> <body>: the block exists with exactly this body
has_block() {
  [[ -f "$1" ]] || return 1
  [[ "$(awk -v s="$BLOCK_START" -v e="$BLOCK_END" '$0==s{f=1;next} $0==e{f=0} f' "$1")" == "$2" ]]
}

# set_block <file> <body>: add the block, or replace its body. Keeps the rest.
set_block() {
  local file="$1" body="$2" tmp b=""
  has_block "$file" "$body" && return 0
  tmp=$(mktemp)
  if [[ -f "$file" ]] && grep -qxF "$BLOCK_START" "$file"; then
    body="$body" awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
      $0==s { print; print ENVIRON["body"]; skip=1; next }
      $0==e { skip=0 }
      !skip' "$file" >"$tmp"
  else
    { [[ -s "$file" ]] && { cat "$file"; echo; }
      printf '%s\n%s\n%s\n' "$BLOCK_START" "$body" "$BLOCK_END"; } >"$tmp"
  fi
  [[ -f "$file" ]] && b=$(backup "$file")
  cat "$tmp" >"$file"; rm -f "$tmp"
  logf "block set in $file${b:+ (backup: $b)}"
}

# drop_block <file>: remove the block. Deletes the file if nothing else is left.
drop_block() {
  local file="$1" tmp
  [[ -f "$file" ]] && grep -qxF "$BLOCK_START" "$file" || return 0
  backup "$file" >/dev/null
  tmp=$(mktemp)
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '$0==s{skip=1;next} $0==e{skip=0;next} !skip' "$file" |
    cat -s >"$tmp"
  if grep -qvE '^[[:space:]]*(#.*)?$' "$tmp"; then cat "$tmp" >"$file"
  else rm -f "$file"; fi
  rm -f "$tmp"
  logf "block removed from $file"
}

# ---------------------------------------------------------------- apt ---

pkg_installed() { [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]; }

# missing_pkgs <pkg...>: prints the ones not installed
missing_pkgs() { local p; for p in "$@"; do pkg_installed "$p" || printf '%s ' "$p"; done; }

as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# apt_install <pkg...>: installs only what's missing
apt_install() {
  local missing; missing=$(missing_pkgs "$@")
  [[ -z "$missing" ]] && return 0
  say "      installing: $missing${D}(sudo may ask for your password)${R}"
  # shellcheck disable=SC2086
  as_root apt-get install -y $missing >>"$log_file" 2>&1 || {
    as_root apt-get update >>"$log_file" 2>&1
    as_root apt-get install -y $missing >>"$log_file" 2>&1
  }
}

# ---------------------------------------------------------- checklist ---
# checklist "<title>" "<label>"... → sets CHECKLIST (array of chosen indexes).
# Labels are "name<TAB>description"; a label "## Group" is a heading (not
# selectable). ↑/↓ or j/k move, space toggles, a toggles all, enter confirms,
# q cancels. CHECKLIST_ON="0 2" pre-ticks those indexes. Uses gum when GUM is set.

checklist() {
  local title="$1"; shift
  local -a items=("$@") on=()
  local n=${#items[@]} cur=-1 i key rest all
  CHECKLIST=()
  (( n )) || return 1
  for (( i = 0; i < n; i++ )); do on[i]=0; done
  for i in ${CHECKLIST_ON:-}; do on[i]=1; done

  if [[ -n "${GUM:-}" ]]; then
    _cl_gum "$title" && return 0
    (( $? == 1 )) && return 1   # 2 = gum can't show this one; use the built-in list
  fi

  _cl_head() { [[ "${items[$1]}" == "## "* ]]; }
  for (( i = 0; i < n; i++ )); do _cl_head "$i" || { cur=$i; break; }; done
  (( cur >= 0 )) || return 1
  # move <step>: to the next selectable row in that direction
  _cl_move() { local j=$cur; while :; do (( j = (j + $1 + n) % n )); _cl_head "$j" || break; done; cur=$j; }

  # Each row is cut to the terminal width: a wrapped line would throw off the redraw.
  _cl_draw() {
    local i mark ptr name desc room cols
    cols=$(tput cols 2>/dev/null || echo 80)
    for (( i = 0; i < n; i++ )); do
      if _cl_head "$i"; then printf '\r\e[K  %s\n' "$B${items[i]#\#\# }$R"; continue; fi
      if (( on[i] )); then mark="${G}[✓]${R}"; else mark="[ ]"; fi
      if (( i == cur )); then ptr="${C}▶${R}"; else ptr=" "; fi
      name=${items[i]%%$'\t'*}; desc=""
      [[ "${items[i]}" == *$'\t'* ]] && desc=${items[i]#*$'\t'}
      room=$(( cols - 24 ))
      (( room < 0 )) && room=0
      (( ${#desc} > room )) && desc="${desc:0:$(( room > 1 ? room - 1 : 0 ))}…"
      printf '\r\e[K  %s %s %-15s %s\n' "$ptr" "$mark" "${name:0:15}" "$D$desc$R"
    done
    local hint="↑ ↓  move    space  select    a  all    enter  confirm    q  cancel"
    (( ${#hint} > cols - 3 )) && hint="↑↓ move · space select · a all · enter ok · q cancel"
    printf '\r\e[K  %s%s%s' "$D" "${hint:0:$(( cols > 3 ? cols - 3 : 0 ))}" "$R"
  }

  printf '%s\n' "$title" >/dev/tty
  printf '\e[?25l' >/dev/tty
  trap 'printf "\e[?25h" >/dev/tty' RETURN
  _cl_draw >/dev/tty
  while true; do
    IFS= read -rsn1 key </dev/tty
    if [[ "$key" == $'\e' ]]; then IFS= read -rsn2 -t 0.05 rest </dev/tty; key+="$rest"; fi
    case "$key" in
      $'\e[A'|k) _cl_move -1 ;;
      $'\e[B'|j) _cl_move 1 ;;
      ' ') (( on[cur] = !on[cur] )) ;;
      a) all=1; for (( i = 0; i < n; i++ )); do _cl_head "$i" || (( on[i] )) || all=0; done
         for (( i = 0; i < n; i++ )); do _cl_head "$i" || on[i]=$(( !all )); done ;;
      '') break ;;
      q|$'\e') printf '\n' >/dev/tty; return 1 ;;
    esac
    printf '\r\e[%dA' "$n" >/dev/tty
    _cl_draw >/dev/tty
  done
  printf '\n' >/dev/tty
  for (( i = 0; i < n; i++ )); do _cl_head "$i" || (( ! on[i] )) || CHECKLIST+=("$i"); done
  return 0
}

# _cl_gum: the same list in `gum choose`. Uses checklist's items/on/n.
# 0 = picked, 1 = cancelled, 2 = can't (gum only pre-ticks all or nothing).
# Rows under the first heading get a ★ (gum has no headings).
_cl_gum() {
  local title="$1" i name desc star="" first="" ticked=0 rows=0 out
  local -a opts=() sel=()
  for (( i = 0; i < n; i++ )); do
    if [[ "${items[i]}" == "## "* ]]; then
      if [[ -z "$first" ]]; then first=${items[i]#\#\# }; star="★"; else star=" "; fi
      continue
    fi
    name=${items[i]%%$'\t'*}; desc=""
    [[ "${items[i]}" == *$'\t'* ]] && desc=${items[i]#*$'\t'}
    opts+=("$(printf '%s%-15s %s' "${star:+$star }" "$name" "$desc")"$'\x1f'"$i")
    (( rows++ )); (( on[i] )) && (( ticked++ ))
  done
  if (( ticked == rows )); then sel=(--selected='*')
  elif (( ticked )); then return 2; fi
  [[ -n "$first" ]] && title+="    ★ = $first"
  # gum's own key hints are too dim to read on some backgrounds and can't be
  # restyled, so they're off and the header carries them instead.
  title+=$'\n'"x  select    ↑ ↓  move    ctrl+a  all    enter  confirm    esc  cancel"
  out=$(printf '%s\n' "${opts[@]}" | "$GUM" choose --no-limit --no-show-help "${sel[@]}" \
          --label-delimiter=$'\x1f' --header="$title" --height=$(( rows + 3 )) 2>/dev/tty) || return 1
  [[ -n "$out" ]] && mapfile -t CHECKLIST < <(sort -n <<<"$out")
  return 0
}
