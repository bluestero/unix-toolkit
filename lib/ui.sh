# Shared look and command rules for every toolkit command (okcli, kx, twin, ws,
# k-bg, ctx). Sourced, not executed.
#
# The command norm. Every tool uses these words for these jobs, and anything
# else is an error (ui_unknown). Internal hooks for scripts start with __.
#
#   <tool>                   the picker
#   <tool> <name>            switch this terminal to <name>
#   <tool> ls | list         everything, as a table
#   <tool> st | status       what this terminal is using now
#   <tool> cur | current     just the active name, for scripts
#   <tool> default [name]    show / set what new terminals start on
#   <tool> off               stop using it in this terminal
#   <tool> doctor            check the setup
#   <tool> help | -h | --help
#
# Tool-specific commands get one name each (no extra aliases). Options that
# change how a command runs stay flags (--yes).

shopt -s extglob

ui_no_color() {
  C_RESET="" C_BOLD="" C_DIM="" C_LINE="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_KEY="" C_WORD=""
}

# Force colour on, e.g. when output feeds fzf (--ansi) from a reload with no tty.
# C_DIM is a solid light grey for secondary text and C_LINE a darker one for
# box lines. Never SGR 2 "faint": it vanishes on kitty's background images.
ui_color() {
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[38;5;248m' C_LINE=$'\e[38;5;244m'
  C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
  C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
  # Roles take different slots of the palette, so a theme or a k-bg image colours each
  # differently: accent = bright blue (12), key hints = bright magenta (13), the
  # counter = bright cyan (14), matches = bright green (10), words = light grey.
  C_KEY=$'\e[95m' C_WORD=$'\e[37m'
  # the accent (prompt, title, pointer, open tab) is the theme's bright blue, so it
  # changes with k-theme
  C_CYAN=$'\e[94m'
}

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then ui_color; else ui_no_color; fi

info() { printf '%s\n' "$*" >&2; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ui_unknown <tool> <word> [what else it could have been, e.g. "profile"]
ui_unknown() {
  die "unknown command${3:+ or $3} '$2' · see: $1 help"
}

# A fix to run, shown after a problem: "expired → okcli refresh"
ui_hint() { printf '%s→ %s%s' "$C_DIM" "$*" "$C_RESET"; }

confirm() {
  local prompt="$1" default="${2:-y}" reply
  [[ -t 0 ]] || return 1   # never act on a default without a human to ask
  # A small picker with the default on top; esc means no. (Inside a kx list,
  # questions go in the list's own header instead: kube/lib/list.sh.)
  if command -v fzf >/dev/null && [[ -e /dev/tty ]]; then
    local yes="Yes" no="No" first second
    if [[ "$default" == y ]]; then first=$yes second=$no; else first=$no second=$yes; fi
    local q; q=$(fold -s -w $(( $(ui_cols) - 10 )) <<<"$prompt" | sed "s/^/${C_BOLD}/; s/\$/${C_RESET}/")
    reply=$(printf '%s\n%s\n' "$first" "$second" | ui_fzf "${UI_CONFIRM_LABEL:-confirm}" \
      --height=~60% --info=hidden --no-separator --prompt='  ' --header="$q") || return 1
    [[ "$reply" == "$yes" ]]; return
  fi
  if [[ "$default" == y ]]; then read -r -p "$prompt [Y/n] " reply </dev/tty
  else read -r -p "$prompt [y/N] " reply </dev/tty; fi
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ui_ask <question> [prefilled answer] -> prints what was typed; fails on esc.
# Like confirm: a small box in place, the answer typed on its prompt line.
ui_ask() {
  local q="$1" pre="${2:-}" out rc
  [[ -t 0 ]] || return 1
  if command -v fzf >/dev/null; then
    q=$(fold -s -w $(( $(ui_cols) - 10 )) <<<"$q" | sed "s/^/${C_BOLD}/; s/\$/${C_RESET}/")
    out=$(: | ui_fzf "${UI_CONFIRM_LABEL:-answer}" --height=~60% --info=hidden --no-separator --disabled \
      --print-query --query="$pre" --prompt='> ' --header="$q"$'\n'"${C_DIM}enter: ok · esc: cancel${C_RESET}")
    rc=$?
    (( rc == 0 || rc == 1 )) || return 1   # 1 = enter with no list to pick from
    out=${out%%$'\n'*}
    out=${out#"${out%%[![:space:]]*}"}; printf '%s' "${out%"${out##*[![:space:]]}"}"   # trim spaces
  else
    read -r -p "$q " out </dev/tty || return 1
    printf '%s' "${out:-$pre}"
  fi
}

# Shell code for the calling shell's wrapper function to source.
emit_eval() {
  [[ -n "${UI_EVAL_FILE:-}" ]] || return 1
  printf '%s\n' "$*" >>"$UI_EVAL_FILE"
}

strip_ansi() { printf '%s' "${1//$'\e['*([0-9;])m/}"; }

# Width on screen, for awk (mawk counts bytes): vis(s) is how many columns s takes, colours
# left out, a CJK or emoji character counting 2. ch(s) is the length in bytes of its first
# character, chw(c) the columns of one character. Prepended to the awk programs below.
_UI_AWK='BEGIN { WIDE = "^(\341[\204\205][\200-\277]|\342[\272-\277][\200-\277]|[\343-\352][\200-\277][\200-\277]|[\353\354][\200-\277][\200-\277]|\355[\200-\236][\200-\277]|\357[\244-\253][\200-\277]|\357\274[\200-\277]|\357\275[\200-\240]|\357\277[\240-\246]|\360\237[\214-\233][\200-\277]|\360\237[\244-\253][\200-\277]|\360[\240-\277][\200-\277][\200-\277])"
  WIDES = substr(WIDE, 2) }
function plain(s) { gsub(/\033\[[0-9;]*m/, "", s); return s }
function vis(s,  w) { s = plain(s); w = gsub(WIDES, "", s) * 2; w += gsub(/[\300-\367][\200-\277]*/, "", s); return w + length(s) }
function ch(s,  c) { c = substr(s, 1, 1); return c ~ /[\300-\337]/ ? 2 : c ~ /[\340-\357]/ ? 3 : c ~ /[\360-\367]/ ? 4 : 1 }
function chw(c) { return c ~ WIDE ? 2 : 1 }
function spaces(n) { return n > 0 ? sprintf("%" n "s", "") : "" }
# s cut to n columns, ending in … (colours kept up to the cut, then reset)
function fit(s, n, rs,  out, v, m, c, w) {
  out = ""; v = 0
  while (s != "") {
    if (match(s, /^\033\[[0-9;]*m/)) { out = out substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1); continue }
    m = ch(s); c = substr(s, 1, m); w = chw(c)
    if (v + w > n - 1) break
    out = out c; v += w; s = substr(s, m + 1)
  }
  return out spaces(n - 1 - v) "…" rs
}
'

# Aligns rows from stdin (cells separated by \x1f) on their visible width.
# Usage: print_table [min gap between columns, default 2] [width to fill] [file for clipped values]
# With a width (pickers pass ui_pick_width): first no cell is clipped, the gaps stay at
# the minimum. When there's room left, the gaps grow, up to 8. When there
# isn't, the widest columns are cut with … (the short ones keep their full width, no
# column goes under its title). With a file, each row that was cut adds a line to it:
# "<row without colors>\036<cell 1>\036<cell 2>..." where a cut cell is "TITLE full value"
# and the others are empty (ui_fzf's footer shows the one under the cursor).
# Anything after a TAB in the last cell is hidden data for fzf and isn't counted.
# Sortable pickers also set UI_TABLE_FIELD (lay out only that TAB field; the others stay)
# and UI_TABLE_ORDER (the columns in this order, e.g. 2,1,3).
# One awk pass: a 400-row table takes a few ms at any width.
print_table() {
  awk -v gap="${1:-2}" -v fill="${2:-0}" -v full="${3:-}" -v rs="$C_RESET" \
      -v f="${UI_TABLE_FIELD:-0}" -v order="${UI_TABLE_ORDER:-}" "$_UI_AWK"'
    { L[NR] = $0 }
    END {
      np = order != "" ? split(order, P, ",") : 0
      for (r = 1; r <= NR; r++) {
        t = L[r]; if (f) { split(t, F, "\t"); t = F[f] }
        TL[r] = ""
        if (!f && (k = index(t, "\t"))) { TL[r] = substr(t, k); t = substr(t, 1, k - 1) }
        n = t == "" ? 0 : split(t, c, "\037")
        if (np && n) { for (i = 1; i <= np; i++) C[r, i] = (P[i] in c) ? c[P[i]] : ""; n = np }
        else for (i = 1; i <= n; i++) C[r, i] = c[i]
        N[r] = n; if (n > cols) cols = n
        for (i = 1; i <= n; i++) { w = V[r, i] = vis(C[r, i]); if (w > W[i]) W[i] = w }
      }
      for (i = 1; i <= cols; i++) { E[i] = W[i]; total += W[i]; if (W[i] > lim) lim = W[i] }
      if (fill > 0 && cols > 1) {
        room = fill - gap * (cols - 1)
        if (total <= room) {
          extra = int((room - total) / (cols - 1))
          if (gap + extra > 8) extra = 8 - gap   # at most 8 between columns
          if (extra > 0) gap += extra
        } else {
          while (lim > 1) {   # the widest width every column can keep
            s = 0; for (i = 1; i <= cols; i++) s += W[i] > lim ? lim : W[i]
            if (s <= room) break
            lim--
          }
          for (i = 1; i <= cols; i++) {
            T[i] = plain(C[1, i])
            if (W[i] > lim) { tw = vis(T[i]); E[i] = lim > tw ? lim : tw }
          }
        }
      }
      if (full != "") printf "" > full
      for (r = 1; r <= NR; r++) {
        n = N[r]; out = ""; clip = ""; cut = 0
        for (i = 1; i <= n; i++) {
          cell = C[r, i]; w = V[r, i]
          if (w > E[i]) {
            if (r > 1) { clip = clip (T[i] == "" ? "?" : T[i]) " " plain(cell); cut = 1 }
            cell = fit(cell, E[i], rs); w = E[i]
          }
          out = out cell (i < n ? spaces(E[i] - w + gap) : "")
          if (i < n) clip = clip "\036"
        }
        out = out TL[r]
        if (f) { m = split(L[r], F, "\t"); F[f] = out; out = F[1]; for (i = 2; i <= m; i++) out = out "\t" F[i] }
        print out
        if (full != "" && cut) print plain(out) "\036" clip > full
      }
    }'
}
# The room a picker row has: the window less fzf's border, padding, pointer and marks.
# Inside fzf (a reload) it's fzf's own width now, so a resized window counts. fzf's
# FZF_COLUMNS already leaves out the border and its padding (4 columns), so both
# give the same width, and the first reload doesn't lay the table out again.
ui_pick_width() {
  if [[ -n "${FZF_COLUMNS:-}" ]]; then printf '%s' $(( FZF_COLUMNS - 4 ))
  else printf '%s' $(( $(ui_cols) - 8 )); fi
}
# The room the header's key hints have: beside a pane on the right, up to the pane
# (fzf tells a callback where it is; a line can be 7 columns shorter than its left edge);
# otherwise the whole row.
ui_header_width() {
  if (( ${FZF_PREVIEW_COLUMNS:-0} > 0 && ${FZF_PREVIEW_LEFT:-0} > 4 )); then printf '%s' $(( FZF_PREVIEW_LEFT - 7 ))
  else ui_pick_width; fi
}

# Cut a line (with colors) to n visible characters, ending in …
ui_fit() {
  local line="$1" n="$2" plain out="" vis=0 i=0 c seq
  plain=$(strip_ansi "$line")
  (( ${#plain} <= n )) && { printf '%s' "$line"; return; }
  while (( i < ${#line} && vis < n - 1 )); do
    c=${line:i:1}
    if [[ "$c" == $'\e' ]]; then
      seq=${line:i}; seq=${seq%%m*}m; out+=$seq; (( i += ${#seq} )); continue
    fi
    out+=$c; (( vis++, i++ ))
  done
  printf '%s…%s' "$out" "$C_RESET"
}

# Red-background badge, e.g. ui_badge PROD. The one loud thing on a screen.
ui_badge() {
  if [[ -n "$C_RESET" ]]; then printf '%s' $'\e[1;41;97m'" $1 $C_RESET"
  else printf '[%s]' "$1"; fi
}

# Terminal width (COLUMNS isn't exported to scripts, and tput reads a piped stdin).
ui_cols() {
  local cols=${COLUMNS:-$({ stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)}
  [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 )) || cols=$(tput cols 2>/dev/null || echo 120)
  (( cols > 20 )) || cols=120
  printf '%s' "$cols"
}

# Rounded box around stdin lines, capped at the terminal width.
# Usage: ui_box <title> [right-side label] [line number to put a rule under] [footer]
#   ╭─ title ───────── right ─╮
#   │  line 1                 │
#   ├─────────────────────────┤
#   │  line 2 …               │
#   ╰─ footer ────────────────╯
# The footer is for one fix that covers the whole box ("→ okcli refresh").
ui_box() {
  local title="$1" right="${2:-}" rule="${3:-0}" foot="${4:-}" b="$C_LINE" r="$C_RESET" fw
  local -a lines=(); local line plain w=0 tw rw cols n i pad='  '
  while IFS= read -r line; do lines+=("$line"); done
  for line in "${lines[@]}"; do
    plain=$(strip_ansi "$line"); (( ${#plain} > w )) && w=${#plain}
  done
  plain=$(strip_ansi "$title"); tw=${#plain}
  plain=$(strip_ansi "$right"); rw=${#plain}
  # w = inner width; each line is │ + pad + w + pad + │
  # top border needs room for: ╭─ title ─ right ─╮
  if (( rw )); then (( w < tw + rw + 3 )) && w=$(( tw + rw + 3 ))
  else (( w < tw )) && w=$tw; fi
  cols=$(ui_cols)
  (( w > cols - 6 )) && w=$(( cols - 6 ))
  if (( rw && tw + rw + 3 > w )); then  # label too long for a narrow terminal
    right=$(ui_fit "$right" $(( w - tw - 3 ))); plain=$(strip_ansi "$right"); rw=${#plain}
  fi
  dashes() { local s; printf -v s '%*s' "$1" ''; printf '%s' "${s// /─}"; }

  if (( rw )); then n=$(( w - tw - rw - 2 )); (( n < 1 )) && n=1
    printf '%s╭─ %s%s %s %s%s %s─╮%s\n' "$b" "$r$C_BOLD$title$r" "$b" "$(dashes "$n")" "$r" "$right" "$b" "$r"
  else n=$(( w - tw + 1 ))
    printf '%s╭─ %s%s %s╮%s\n' "$b" "$r$C_BOLD$title$r" "$b" "$(dashes "$n")" "$r"
  fi
  # one blank line of air at the top and bottom of every box
  local blank; printf -v blank '%s│%s%*s%s│%s' "$b" "$r" $(( w + 4 )) '' "$b" "$r"
  printf '%s\n' "$blank"
  for i in "${!lines[@]}"; do
    line=$(ui_fit "${lines[i]}" "$w"); plain=$(strip_ansi "$line")
    printf '%s│%s%s%s%*s%s%s│%s\n' "$b" "$r" "$pad" "$line" $(( w - ${#plain} )) '' "$pad" "$b" "$r"
    (( i + 1 == rule )) && printf '%s├%s┤%s\n' "$b" "$(dashes $(( w + 4 )))" "$r"
  done
  printf '%s\n' "$blank"
  if [[ -n "$foot" ]]; then
    plain=$(strip_ansi "$foot"); fw=${#plain}
    if (( fw + 3 > w + 4 )); then foot=$(ui_fit "$foot" $(( w + 1 ))); plain=$(strip_ansi "$foot"); fw=${#plain}; fi
    printf '%s╰─ %s%s %s╯%s\n' "$b" "$r$foot" "$b" "$(dashes $(( w + 4 - fw - 3 )))" "$r"
  else
    printf '%s╰%s╯%s\n' "$b" "$(dashes $(( w + 4 )))" "$r"
  fi
}

# A table in a box (or plain when piped, so it greps and diffs cleanly).
# Usage: ... | ui_table <title> [right-side label] [footer]    rows as for
# print_table, the first row is the header (bold it yourself).
ui_table() {
  if [[ -t 1 ]]; then print_table 3 | ui_box "$1" "${2:-}" 1 "${3:-}"
  else print_table 3; fi
}

# key/value lines in a box: rows "key<TAB>value". Plain when piped.
# Usage: ... | ui_fields <title> [right-side label]
ui_fields() {
  local k v S=$'\x1f'
  while IFS=$'\t' read -r k v; do
    if [[ -z "$k" ]]; then printf '\n'; else printf '%s%s%s\n' "$C_DIM$k$C_RESET" "$S" "$v"; fi
  done | if [[ -t 1 ]]; then print_table 3 | ui_box "$1" "${2:-}"; else print_table 3; fi
}

# Help page, same layout for every tool.
# Usage: ui_help <tool> <one-line summary> <<'EOF'
#   ## Heading                     a section title
#   cmd<TAB>what it does[<TAB>note]  a command row; the note shows in grey
#   anything else                  a grey note line
#   (empty line)                   a gap
# EOF
ui_help() {
  local tool="$1" summary="$2" line cmd desc note w=0 dw=0 ind=""
  local -a lines=()
  [[ -t 1 ]] || ui_no_color
  while IFS= read -r line; do
    lines+=("$line")
    [[ "$line" == '## '* ]] && ind="  "
    if [[ "$line" == *$'\t'* ]]; then
      cmd=${line%%$'\t'*}; desc=${line#*$'\t'}
      (( ${#cmd} > w )) && w=${#cmd}
      [[ "$desc" == *$'\t'* ]] && { desc=${desc%%$'\t'*}; (( ${#desc} > dw )) && dw=${#desc}; }
    fi
  done
  for line in "${lines[@]}"; do
    if [[ "$line" == '## '* ]]; then printf '%s\n' "$C_BOLD${line#'## '}$C_RESET"
    elif [[ "$line" == *$'\t'* ]]; then
      cmd=${line%%$'\t'*}; desc=${line#*$'\t'}
      if [[ "$desc" == *$'\t'* ]]; then
        note=${desc#*$'\t'}; desc=${desc%%$'\t'*}
        printf '%s%s%s%s%*s   %s%*s   %s\n' "$ind" "$C_CYAN" "$cmd" "$C_RESET" $(( w - ${#cmd} )) '' \
          "$desc" $(( dw - ${#desc} )) '' "$C_DIM$note$C_RESET"
      else
        printf '%s%s%s%s%*s   %s\n' "$ind" "$C_CYAN" "$cmd" "$C_RESET" $(( w - ${#cmd} )) '' "$desc"
      fi
    elif [[ -z "$line" ]]; then printf '\n'
    else printf '%s%s%s%s\n' "$ind" "$C_DIM" "$line" "$C_RESET"; fi
  done | if [[ -t 1 ]]; then ui_box "$tool" "$summary"; else cat; fi
}

# A tab strip, one row, bordered on the left of the first tab and the right of the
# last: │ Mine 10 │ All 416 │. The open tab is bold in the accent, the others grey.
#   ui_tabs <open index, from 0> <label>...      (labels are plain text)
ui_tabs() {
  local act=$1 i=0 l out="$C_LINE│$C_RESET"; shift
  for l in "$@"; do
    if (( i == act )); then out+="$C_CYAN$C_BOLD $l $C_RESET"; else out+="$C_WORD $l $C_RESET"; fi
    out+="$C_LINE│$C_RESET"; i=$((i + 1))
  done
  printf '%s' "$out"
}

# Key hints for a picker header. Takes the plain form every tool writes,
#   "enter: switch · ctrl-d: make default · esc: cancel"   (several lines join one grid)
# and shows each key in the accent colour with its words in grey, then a
# divider, so the hints never blur into the list's own column headings.
# A header that already has colours (k-bg) only gets the divider.
# A line starting with ! is a warning row (amber), !! a loud one (red).
# The hints sit in a grid: up to 5 columns (as many as fit), every row using the same
# column widths, each hint ("key words") starting at its column's left edge. The hints
# fill the rows in the order given (a tool's own keys first, then the common ones). A
# warning line (! or !!) stays one line of its own, above the grid.
# A note line ("# ↑ means …", what marks in the list mean) goes above the keys, grey,
# with a blank line under it.
ui_keys() {   # ui_keys <header text> [max divider width]
  local text="$1" max="${2:-}" line item out="" warn="" note="" row w=0 plain kc wc room i c n cols tot pad
  local -a key=() words=() kcol=() wcol=() kw=()
  room=$(ui_header_width)
  if [[ "$text" == *$'\e['* ]]; then out="$text"
  else
    while IFS= read -r line; do   # every hint: key, words, colours
      kc="$C_KEY" wc="$C_WORD"
      # "# text": a note (what marks in the list mean), grey, on its own above the keys
      if [[ "$line" == '# '* ]]; then note+="${note:+$'\n'}$C_DIM${line#'# '}$C_RESET"; continue; fi
      if [[ "$line" == '!'* ]]; then   # a warning: one line, amber (! ) or red (!!)
        if [[ "$line" == '!!'* ]]; then line=${line#!!}; kc=$'\e[1;31m' wc=$C_RED
        else line=${line#!}; kc=$'\e[1;33m' wc=$C_YELLOW; fi
        row=""
        while [[ -n "$line" ]]; do
          item=${line%%' · '*}
          if [[ "$item" == "$line" ]]; then line=""; else line=${line#*' · '}; fi
          if [[ "$item" =~ ^([^\ :]+):\ (.*)$ ]]; then row+="${row:+   }$kc${BASH_REMATCH[1]}$C_RESET $wc${BASH_REMATCH[2]}$C_RESET"
          else row+="${row:+   }$kc$item$C_RESET"; fi
        done
        warn+="${warn:+$'\n'}$row"; continue
      fi
      while [[ -n "$line" ]]; do
        item=${line%%' · '*}
        if [[ "$item" == "$line" ]]; then line=""; else line=${line#*' · '}; fi
        if [[ "$item" =~ ^([^\ :]+):\ (.*)$ ]]; then key+=("${BASH_REMATCH[1]}") words+=("${BASH_REMATCH[2]}")
        else key+=("$item") words+=(""); fi
        kcol+=("$kc") wcol+=("$wc")
      done
    done <<<"$text"
    # the most columns that fit: each column as wide as its widest hint
    for (( cols = 5; cols >= 1; cols-- )); do
      kw=() c=0
      for i in "${!key[@]}"; do
        n=$(( ${#key[i]} + (${#words[i]} ? ${#words[i]} + 1 : 0) ))
        (( n > ${kw[c]:-0} )) && kw[c]=$n
        (( c = (c + 1) % cols ))
      done
      tot=0; for c in "${!kw[@]}"; do (( tot += kw[c] + (c ? 3 : 0) )); done
      (( tot <= room || cols == 1 )) && break
    done
    c=0 row=""
    for i in "${!key[@]}"; do
      if (( i > 0 && c == 0 )); then out+="${out:+$'\n'}${row%"${row##*[! ]}"}"; row="" c=0; fi
      n=$(( ${#key[i]} + (${#words[i]} ? ${#words[i]} + 1 : 0) ))
      printf -v pad '%*s' $(( kw[c] - n + 3 )) ''
      row+="${kcol[i]}${key[i]}$C_RESET${words[i]:+ ${wcol[i]}${words[i]}$C_RESET}$pad"
      (( c = (c + 1) % cols ))
    done
    out+="${out:+$'\n'}${row%"${row##*[! ]}"}"
    out="${warn:+$warn$'\n'}$out"
    out="${note:+$note$'\n\n'}$out"
  fi
  # The divider is as wide as the longest hint line (and fits beside a pane).
  while IFS= read -r line; do plain=$(strip_ansi "$line"); (( ${#plain} > w )) && w=${#plain}; done <<<"$out"
  # Inside fzf (a callback), the room already stops at the pane when it shows.
  [[ -n "$max" && -z "${FZF_COLUMNS:-}" ]] && (( w > max )) && w=$max
  (( w > room )) && w=$room
  (( w > 0 )) || w=20
  printf '%s\n%s' "$out" "$C_LINE$(printf '─%.0s' $(seq "$w"))$C_RESET"
}

# ui_fzf_at_least <version>: is the fzf on PATH at least that new? (asked once per run)
ui_fzf_at_least() {
  [[ -n "${_UI_FZF_VER+x}" ]] || _UI_FZF_VER=$(fzf --version 2>/dev/null | awk '{print $1}')
  [[ -n "$_UI_FZF_VER" && "$(printf '%s\n%s\n' "$1" "$_UI_FZF_VER" | sort -V | head -1)" == "$1" ]]
}

# ------------------------------------------------------- sortable tables ---
# ui_fzf --sortable: the input is a table, title row first (--header-lines=1).
# A column starts where its title starts (print_table and kubectl both line up so).
#   alt-← / alt-→  move the cursor between columns (its title is underlined); the sort stays
#   alt-s          sort the cursor's column: original → A→Z ▼ → Z→A ▲ → original (the mark)
#   click          a title: the cursor goes there and it is sorted (again: next way)
#   alt-shift-←/→  move the cursor's column
# The title row is shown as the last line of fzf's --header (not as a header line of the
# input), so a cursor move only changes the header: no reload, no flicker. In $UI_SORT_DIR:
#   state   "<cursor column> <sorted column> <none|asc|desc>"
#   cells   the table as given (\x1f cells, never cut), when it has cells
#   rows    the table laid out, title row first
#   hints   the header above the title row; title: the title row as shown
#   view    the rows in the state's order, made before a reload-sync shows them
# With --delimiter=$'\t' --with-nth=N, the table is field N (the rest is hidden).
# A picker that reloads its own rows pipes them through ui_sort_feed; one that changes
# its header passes the new one through ui_sort_header, so the title row stays under it.
# One that draws its own header above the table: --sortable=<line> (kept as laid out).

# Lays the cells out for the width fzf has now, in the order of $d/swaps, from their full
# text (a cell cut before is cut again from all of it). Only when the width or the order
# changed. Writes $d/rows, $d/full for the footer, $d/layout_key.
ui_sort_layout() {
  local d="$UI_SORT_DIR" f="${UI_SORT_FIELD:-0}" n i k t key order=""
  local -a perm=()
  key="$(ui_pick_width):$(tr '\n' , <"$d/swaps")"
  [[ -s "$d/rows" && "$(cat "$d/layout_key" 2>/dev/null)" == "$key" ]] && return 0
  n=$(head -1 "$d/cells" | awk -F '\t' -v f="$f" '{ t = f ? $f : $0; sub(/\t.*/, "", t); print split(t, c, "\037") }')
  for (( i = 1; i <= n; i++ )); do perm+=("$i"); done
  while read -r k; do
    (( k >= 1 && k < n )) || continue
    t=${perm[k-1]}; perm[k-1]=${perm[k]}; perm[k]=$t
  done <"$d/swaps"
  (( n > 1 )) && { order="${perm[*]}"; order=${order// /,}; }
  UI_TABLE_FIELD=$f UI_TABLE_ORDER=$order print_table 3 "$(ui_pick_width)" "$d/full" <"$d/cells" >"$d/rows.new" &&
    mv -f "$d/rows.new" "$d/rows"
  printf '%s' "$key" >"$d/layout_key"
}

# The title row as shown: the mark on the sorted title, the cursor's title underlined.
# Writes $d/title, and $d/spans ("<start> <column>", where each title starts).
ui_sort_title() {
  local d="$UI_SORT_DIR" cur=1 col=1 way=none
  read -r cur col way <"$d/state"; cur=${cur:-1} col=${col:-1} way=${way:-none}
  # how wide the laid-out table is (the divider above it reaches its last column)
  if [[ ! -s "$d/width" || "$d/rows" -nt "$d/width" ]]; then
    awk -F '\t' -v f="${UI_SORT_FIELD:-0}" "$_UI_AWK"'{ t = f ? $f : $0; sub(/\t.*/, "", t); w = vis(t); if (w > m) m = w }
      END { print m + 0 }' "$d/rows" >"$d/width"
  fi
  head -1 "$d/rows" | awk -F '\t' -v f="${UI_SORT_FIELD:-0}" -v cur="$cur" -v col="$col" -v way="$way" \
      -v on="$C_CYAN$C_BOLD" -v off="$C_RESET" -v spans="$d/spans" -v title="$d/title" '
    { t = f ? $f : $0; sub(/\t.*/, "", t); gsub(/\033\[[0-9;]*m/, "", t); out = ""; len = 0; p = 1; n = 0
      printf "" > spans
      while (match(substr(t, p), /[^ ]+( [^ ]+)*/)) {   # a title: words split by single spaces
        st = p + RSTART - 1; w = substr(t, st, RLENGTH); p = st + RLENGTH; n++
        print st, n > spans
        pad = st - 1 - len; if (pad < 0) pad = 0
        mark = "  "; if (n == col && way != "none") mark = (way == "asc") ? " ▼" : " ▲"
        shown = (n == cur) ? "\033[4m" w "\033[24m" : w   # the cursor'"'"'s column is underlined
        out = out sprintf("%" (pad ? pad : "") "s", "") on shown mark off; len += pad + length(w) + 2
      }
      printf "%s", out > title }'
}

# The laid-out rows (no title row) in the state's order.
ui_sort_rows() {
  local d="$UI_SORT_DIR" col=1 way=none s e r=""
  read -r _ col way <"$d/state"; col=${col:-1} way=${way:-none}
  if [[ "$way" == none ]]; then tail -n +2 "$d/rows"; return; fi
  s=$(awk -v c="$col" '$2 == c { print $1 }' "$d/spans")
  e=$(awk -v c="$col" '$2 == c + 1 { print $1 }' "$d/spans")
  [[ "$way" == desc ]] && r=r
  # sort on the column's plain text (marks like ● left out); ties keep their order.
  # Columns are counted on screen: a wide character takes 2.
  tail -n +2 "$d/rows" | awk -F '\t' -v f="${UI_SORT_FIELD:-0}" -v s="${s:-1}" -v e="$e" "$_UI_AWK"'
    { t = f ? $f : $0; t = plain(t); gsub(WIDES, "\001\001", t); gsub(/[\300-\367][\200-\277]*/, "\001", t)
      k = e ? substr(t, s, e - s) : substr(t, s); gsub(/\001/, "", k); gsub(/^ +| +$/, "", k)
      if (k ~ /^[0-9]+[smhdwy]([0-9]+[smhdwy])*$/) {   # an age (9d, 4h48m): by length of time, not by letters
        secs = 0; v = k
        while (match(v, /^[0-9]+[smhdwy]/)) {
          u = substr(v, RLENGTH, 1); x = substr(v, 1, RLENGTH - 1) + 0; v = substr(v, RLENGTH + 1)
          secs += x * (u == "s" ? 1 : u == "m" ? 60 : u == "h" ? 3600 : u == "d" ? 86400 : u == "w" ? 604800 : 31536000)
        }
        k = sprintf("%012d", secs)
      }
      print k "\036" NR "\036" $0 }' |
    sort -t $'\036' -k1,1fV$r -k2,2n | cut -d $'\036' -f3-
}

# Laid out again if the window or the column order changed, then the title row
# ($d/title) and the rows in the state's order. What a reload of the picker runs.
ui_sort_render() {
  [[ -z "${NO_COLOR:-}" ]] && ui_color   # a reload has no terminal to go by
  [[ -s "$UI_SORT_DIR/cells" ]] && ui_sort_layout
  ui_sort_title
  ui_sort_rows
}

# The picker's header: <hints> with the title row under it. A sortable picker that
# changes its header (change-header, transform-header) passes the new one through this.
# With no argument, the last hints again. Outside a sortable picker it prints <hints>.
ui_sort_header() {   # [hints]
  local d="${UI_SORT_DIR:-}"
  [[ -n "$d" && -s "$d/title" ]] || { printf '%s' "${1:-}"; return; }
  local hints="" title=""   # read with builtins: this runs on every cursor move
  if (( $# )); then hints=$1; printf '%s' "$hints" >"$d/hints"; else IFS= read -r -d '' hints <"$d/hints" || :; fi
  IFS= read -r -d '' title <"$d/title" || :; printf '%s' "$title" >"$d/title.shown"
  # the divider (the hints' last line) reaches the table's last column when that's wider
  local last=${hints##*$'\n'} tw=0 rule
  if [[ "$last" == "$C_LINE"─*"$C_RESET" && -s "$d/width" ]]; then
    read -r tw <"$d/width"; rule=${last#"$C_LINE"}; rule=${rule%"$C_RESET"}
    if (( ${FZF_PREVIEW_COLUMNS:-0} > 0 && ${FZF_PREVIEW_LEFT:-0} > 4 && tw > FZF_PREVIEW_LEFT - 7 )); then
      tw=$(( FZF_PREVIEW_LEFT - 7 ))   # not into the pane on the right (as ui_header_width)
    fi
    if (( tw > ${#rule} )); then
      printf -v rule '%*s' "$tw" ''; rule=${rule// /─}
      hints="${hints%"$last"}$C_LINE$rule$C_RESET"
    fi
  fi
  printf '%s%s' "${hints:+$hints$'\n'}" "$title"
}
# The same with key hints in their plain form (ui_keys styles them), kept so that a
# resize wraps them again for the new width. <above>: lines shown as they are over them
# (a question, k-theme's tabs). A divider width means "fits beside a pane".
ui_sort_keys() {   # keys [above] [max divider width]
  local d="${UI_SORT_DIR:-}"
  [[ -n "$d" ]] && { printf '%s' "$1" >"$d/keys"; printf '%s' "${2:-}" >"$d/keys.above"; printf '%s' "${3:+pane}" >"$d/keys.max"; }
  ui_sort_header "${2:+$2$'\n'}$(ui_keys "$1" "${3:-}")"
}
# After a resize: the kept key hints wrapped for the width fzf has now.
ui_sort_rekey() {
  local d="$UI_SORT_DIR" keys above max=""
  [[ -e "$d/keys" ]] || return 0
  keys=$(<"$d/keys") above=$(<"$d/keys.above")
  [[ -s "$d/keys.max" ]] && max=$(( (${FZF_COLUMNS:-$(( $(ui_cols) - 4 ))} + 4) * 45 / 100 - 8 ))
  printf '%s' "${above:+$above$'\n'}$(ui_keys "$keys" "$max")" >"$d/hints"
}

# An fzf action with a text argument, in brackets the text doesn't contain.
ui_fz() {   # action text
  local p
  for p in '()' '{}' '<>' '[]' '~~' '!!' '@@' '##' '%%' '^^' '&&' '**' ';;' '//' '||'; do
    [[ "$2" == *"${p:1:1}"* ]] && continue
    printf '%s%s%s%s' "$1" "${p:0:1}" "$2" "${p:1:1}"; return
  done
}

# For a sortable picker that reloads its own rows: `make_rows | ui_sort_feed`.
# Inside it, saves the new rows and prints them sorted; anywhere else, cat.
# The title row goes to the header after the reload (ui_fzf's result: bind).
ui_sort_feed() {
  local d="${UI_SORT_DIR:-}" a
  [[ -d "$d" ]] || { cat; return; }
  cat >"$d/in"; IFS= read -r a <"$d/in" || a=""
  (( ${UI_SORT_FIELD:-0} )) && a=$(cut -f"$UI_SORT_FIELD" <<<"$a")
  if [[ "$a" == *$'\x1f'* ]]; then mv -f "$d/in" "$d/cells"; rm -f "$d/layout_key"
  else rm -f "$d/cells"; mv -f "$d/in" "$d/rows"; ui_cols_reorder "$d/swaps"; fi
  ui_sort_render
}

# Moved columns in a table given laid out (no cells): each alt-shift-←/→ swaps two
# neighbours. ui_cols_reorder <file> redoes the swaps listed in it (one number per line:
# that column and the next trade places) on the saved rows. A move applies its own swap; a
# reload gives rows in the original order, so ui_sort_feed redoes all of $UI_SORT_DIR/swaps.
# Rows are cut into cells where each title starts, put in the new order and laid out again.
ui_cols_reorder() {
  local d="$UI_SORT_DIR" f="${UI_SORT_FIELD:-0}" sep=$'\x1f' k n i line out t
  local -a perm=() cells
  [[ -s "$1" ]] || return 0
  awk -F '\t' -v f="$f" '{ print f ? $f : $0 }' "$d/rows" | ui_split_cols >"$d/t2"
  n=$(head -1 "$d/t2" | awk -F '\037' '{ print NF }')
  for (( i = 1; i <= n; i++ )); do perm+=("$i"); done
  while read -r k; do
    (( k >= 1 && k < n )) || continue
    t=${perm[k-1]}; perm[k-1]=${perm[k]}; perm[k]=$t
  done <"$1"
  while IFS= read -r line; do
    IFS=$sep read -r -a cells <<<"$line"; out=""
    for i in "${perm[@]}"; do out+="${cells[i-1]:-}$sep"; done
    printf '%s\n' "${out%"$sep"}"
  done <"$d/t2" | print_table 3 "$(ui_pick_width)" >"$d/t3"
  awk -F '\t' -v OFS='\t' -v f="$f" 'NR == FNR { t[FNR] = $0; next }
    { if (f) { $f = t[FNR]; print } else print t[FNR] }' "$d/t3" "$d/rows" >"$d/rows.new" && mv "$d/rows.new" "$d/rows"
}

# A key that changes what the rows show without closing the picker (kx's ctrl-d).
# The picker gets --live-rows=CMD (prints the raw table again) and a key bound
# to a command that does its work, then prints `ui_live_reload <position>`:
# the rows are laid out afresh, saved, and the picker reloads on the same row.
ui_live_reload() {   # 1-based position of the row to stay on
  local d="$UI_SORT_DIR"
  [[ -n "${UI_LIVE_ROWS:-}" && -d "$d" ]] || return 0
  ui_color
  bash -c "$UI_LIVE_ROWS" | ui_sort_feed >/dev/null   # kept as cells, so a resize lays them out again
  printf 'pos(%s)' "${1:-1}" >"$d/onload"   # the picker's load: bind (ui_live_onload) moves the cursor back
  printf '%s' "reload(bash -c '. \"\$UI_SORT_LIB\"; ui_sort_render')"
}

# The load: bind for such a picker: the first load puts the cursor on <start>; after
# ui_live_reload, on the row it asked for.
ui_live_onload() {   # start-position -> the --bind to pass
  printf '%s' "load:transform:f=\"\$UI_SORT_DIR/onload\"; if [ -s \"\$f\" ]; then cat \"\$f\"; : >\"\$f\"; else echo 'pos($1)'; fi"
}

# A message in the picker's footer that clears itself after 5 s (like the kx lists).
# Used from a key's callback: prints the fzf action. ui_fzf sets up the rest.
# $UI_TOAST_DIR/id is there while it shows (the cut-cell footer waits for it).
ui_toast() {   # text
  local d="${UI_TOAST_DIR:-}" id
  [[ -d "$d" ]] || { ui_fz change-footer "$1"; return; }
  id=$(date +%s%N); printf '%s' "$id" >"$d/id"
  ( sleep 5; [[ "$(cat "$d/id" 2>/dev/null)" == "$id" ]] && rm -f "$d/id" && printf '%s' "$UI_TOAST_CLEAR" >"$d/todo.$id" ) \
    </dev/null >/dev/null 2>&1 &
  ui_fz change-footer "$1"
}

# ui_sort_step sort | left | right | mvleft | mvright | resize | pane | click <line> <column>:
# prints the fzf actions. A cursor move only changes the header. A sort, a column move or
# a new width makes the view first, then reload-sync shows it (the old rows stay up until
# then, so nothing flickers).
ui_sort_step() {
  local d="$UI_SORT_DIR" cur=1 col=1 way=none was s c k n go=first hdr re foot=""
  local -a starts=() cols=()
  [[ -z "${NO_COLOR:-}" ]] && ui_color
  read -r cur col way <"$d/state"; cur=${cur:-1} col=${col:-1} way=${way:-none} was=$way
  while read -r s c; do starts+=("$s"); cols+=("$c"); done <"$d/spans"
  n=${#cols[@]}; (( n )) || return 0
  case "$1" in
    sort|click)
      if [[ "$1" == click ]]; then   # only the title row (under the hints); from a title to the next one counts
        [[ "${2:-}" == $(( $(grep -c '' "$d/hints" 2>/dev/null) + 1 )) ]] || return 0
        c=1; for k in "${!starts[@]}"; do (( ${3:-0} >= starts[k] )) && c=${cols[k]}; done
        cur=$c
      fi
      if (( cur == col )); then
        case "$way" in none) way=asc ;; asc) way=desc ;; *) way=none ;; esac
      else col=$cur; [[ "$way" == none || "$1" == sort ]] && way=asc; fi ;;
    mvleft|mvright)   # move the cursor's column; the sorted column goes where it went
      if [[ "$1" == mvleft ]]; then k=$(( cur - 1 )); else k=$cur; fi
      (( k >= 1 && k < n )) || return 0
      [[ -s "$d/cells" ]] || { echo "$k" >"$d/one"; ui_cols_reorder "$d/one"; }
      echo "$k" >>"$d/swaps"
      if (( col == k )); then col=$(( k + 1 )); elif (( col == k + 1 )); then col=$k; fi
      if [[ "$1" == mvleft ]]; then cur=$(( cur - 1 )); else cur=$(( cur + 1 )); fi ;;
    left)  cur=$(( (cur - 2 + n) % n + 1 )); go="" ;;   # only the underline moves: no sort, the row stays
    right) cur=$(( cur % n + 1 )); go="" ;;
    pane) ui_sort_rekey; go="" ;;   # the pane opened or closed (chained after change-preview-window): hints re-wrap
    resize) ui_sort_rekey   # the key hints wrap for the new width
            if [[ -s "$d/cells" ]]; then go=stay; else go=""; fi ;;   # the table too, same row
  esac
  echo "$cur $col $way" >"$d/state"
  [[ -n "$go" && -s "$d/cells" ]] && ui_sort_layout
  ui_sort_title
  [[ -e "$d/footer.sh" ]] && foot="+transform-footer(bash $d/footer.sh {})"
  if [[ -z "$go" ]]; then printf '%s' "${foot#+}${foot:++}change-header:$(ui_sort_header)"; return; fi
  ui_sort_rows >"$d/view"
  hdr=$(ui_fz change-header "$(ui_sort_header)")
  re="reload-sync(cat $d/view)"
  # while sorted, fzf mustn't rank matches itself: typing filters, the order stays
  [[ "$was" == none && "$way" != none || "$was" != none && "$way" == none ]] && printf 'toggle-sort+'
  # unbind(load): a picker's load:pos(N) / select-all is for the first load only.
  # A picker with --track (the kx lists) keeps the cursor on the same row through a
  # reload, which would undo `first`: so tracking is off around this one reload.
  if [[ "$go" == stay ]]; then printf '%s' "$hdr+$re$foot"
  elif [[ -n "${UI_SORT_TRACK:-}" ]]; then printf '%s' "unbind(load)+$hdr+toggle-track+$re+first+toggle-track$foot"
  else printf '%s' "unbind(load)+$hdr+$re+first$foot"; fi
}

# A table kubectl-style (columns lined up under their titles, no \x1f) becomes \x1f
# cells, cut where each title starts, so print_table can lay it out. A title is words
# split by single spaces. Positions count characters, as kubectl (Go's tabwriter) pads
# them, not screen columns: a wide character counts 1 here too.
ui_split_cols() {
  awk "$_UI_AWK"'
    # a colour code goes with the text after it (a reset with the text before), so it
    # stays in its own cell even when a neighbour is cut
    function walk(s, title,  out, cell, pend, pe, v, m, c, sp) {
      out = ""; cell = ""; pend = ""; pe = ""; v = 0; sp = 2
      while (s != "") {
        if (match(s, /^\033\[[0-9;]*m/)) {
          c = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
          if (c ~ /^\033\[0?m$/ && pe == "") cell = cell c; else pe = pe c
          continue
        }
        m = ch(s); c = substr(s, 1, m); s = substr(s, m + 1)
        if (title) { if (c != " " && sp >= 2) start[v] = 1; sp = c == " " ? sp + 1 : 0 }
        else if (v > 0 && (v in start)) { out = out cell "\037"; cell = ""; pend = "" }
        if (c == " ") pend = pend " "; else { cell = cell pend pe c; pend = ""; pe = "" }
        v++
      }
      return out cell pe
    }
    NR == 1 { walk($0, 1) }
    { print walk($0, 0) }'
}

# Common fzf look. Usage: ui_fzf <label> [--sortable] <extra fzf args...>
# A --header=... is restyled by ui_keys. Raw table rows (cells split by \x1f, title
# row first) with --header-lines=1 are laid out here; --sortable sorts them (above).
ui_fzf() {
  local label="$1" a h="" hraw="" in="" max="" phide=0 lines=0 sortable=0 multi=0 tline="" nth="" tab=0 track="" toast=0 footer=0; shift
  local -x UI_LIVE_ROWS="" UI_TOAST_DIR="" UI_TOAST_CLEAR="change-footer( )"
  local -a args=()
  for a in "$@"; do
    case "$a" in
      --preview=*) max=$(( $(ui_cols) * 45 / 100 - 8 )) ;;
      --preview-window=*hidden*) phide=1 ;;   # opens without the pane: the header has the whole row
      --header-lines=1) lines=1 ;;
      --sortable) sortable=1 ;;
      --sortable=*) sortable=1 tline=${a#--sortable=} ;;
      --multi) multi=1 ;;
      --track) track=1 ;;
      --live-rows=*) UI_LIVE_ROWS=${a#--live-rows=} ;;
      --toast) toast=1 ;;
      --footer=*) footer=1 ;;
      --with-nth=*) nth=${a#--with-nth=} ;;
      --delimiter=$'\t'|--delimiter='\t') tab=1 ;;
    esac
  done
  (( phide )) && max=""
  (( lines )) || sortable=0
  ui_fzf_at_least 0.60 || sortable=0
  if (( lines )); then   # keep the rows (a reload sorts them), laid out once
    in=$(mktemp -d) || return 1
    cat >"$in/raw"; IFS= read -r a <"$in/raw" || a=""
    if (( sortable )) && [[ "$a" != *$'\x1f'* && -z "$tline" ]] && (( ! tab )); then
      ui_split_cols <"$in/raw" >"$in/cells" && mv "$in/cells" "$in/raw"; a=$'\x1f'
    fi
    local fa=$a   # with TAB fields, the table is field N
    (( tab )) && [[ "$nth" =~ ^[0-9]+$ ]] && fa=$(cut -f"$nth" <<<"$a")
    if (( sortable )) && [[ "$fa" == *$'\x1f'* ]]; then
      mv "$in/raw" "$in/cells"   # laid out by ui_sort_layout, again when the window is resized
    elif [[ "$a" == *$'\x1f'* ]]; then print_table 3 "$(ui_pick_width)" <"$in/raw" >"$in/rows"
    else mv "$in/raw" "$in/rows"; fi
  fi
  local keys="alt-s: sort · alt-←→: column · alt-shift-←→: move it"
  (( sortable )) && [[ " $* " != *' --header='* ]] && set -- "$@" "--header=$keys"
  for a in "$@"; do
    case "$a" in
      --sortable|--sortable=*|--live-rows=*|--toast) ;;
      --header-lines=1) (( sortable )) || args+=("$a") ;;   # sortable: the title row goes in the header
      --header=*)
        h=${a#--header=}
        if (( sortable )) && [[ "$h" != *'alt-s:'* ]]; then
          if [[ "$h" == *'esc: cancel'* ]]; then h=${h/esc: cancel/$keys · esc: cancel}; else h+=" · $keys"; fi
        fi
        hraw=$h h=$(ui_keys "$h" "$max"); (( sortable )) || args+=("--header=$h") ;;
      *) args+=("$a") ;;
    esac
  done
  # The counter: where you are, not just how many match. fzf's own "426/426" is
  # matches/total, so it never moves while you scroll. Needs fzf 0.60+ (tk install fzf).
  if ui_fzf_at_least 0.60; then
    args+=("--info-command=printf '%s/%s' \"\$FZF_POS\" \"\$FZF_MATCH_COUNT\"; [ \"\$FZF_MATCH_COUNT\" = \"\$FZF_TOTAL_COUNT\" ] || printf ' of %s' \"\$FZF_TOTAL_COUNT\"; [ \"\${FZF_SELECT_COUNT:-0}\" -gt 0 ] && printf ' · %s ticked' \"\$FZF_SELECT_COUNT\"; true")
  fi
  # --cycle: up on the first row goes to the last, down on the last to the first.
  # --height=100%: the whole window on fzf's own screen, so resizing leaves no
  # broken borders behind. confirm and ui_ask pass ~60% to stay small boxes in place.
  (( toast )) && { UI_TOAST_DIR=$(mktemp -d) || UI_TOAST_DIR=""; }
  [[ -n "$UI_TOAST_DIR" ]] && args+=("--bind=every(0.5):+transform:f=\$(ls \"\$UI_TOAST_DIR\"/todo.* 2>/dev/null | head -1); [ -n \"\$f\" ] && cat \"\$f\" && rm -f \"\$f\"")
  local -a cmd=(fzf --ansi --reverse --cycle --height=100% --border=rounded --info=inline --bind=alt-bs:backward-kill-word --bind=ctrl-h:backward-kill-word
    --border-label=" $label " --pointer='▶' --marker='✓'
    --color="pointer:12,prompt:12,label:12,marker:green,header:248,border:244,info:14,hl:10,hl+:10,spinner:13")
  local rc=0
  if (( sortable )); then
    local -x UI_SORT_DIR="$in" UI_SORT_LIB UI_SORT_FIELD=0 UI_SORT_TRACK="$track"
    UI_SORT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"
    (( tab )) && [[ "$nth" =~ ^[0-9]+$ ]] && UI_SORT_FIELD=$nth
    : >"$in/state"; : >"$in/swaps"
    ui_sort_render >"$in/view"
    args+=("--header=$(ui_sort_keys "$hraw" "" "$max")")
    # The title row in the header follows the rows: after a reload from the picker
    # (ui_sort_feed) its columns may have moved, so the header is put back together.
    printf '%s\n' 'cmp -s "$UI_SORT_DIR/title" "$UI_SORT_DIR/title.shown" && exit 0' \
      'cp -f "$UI_SORT_DIR/title" "$UI_SORT_DIR/title.shown"; printf "change-header:"' \
      '[ -s "$UI_SORT_DIR/hints" ] && { cat "$UI_SORT_DIR/hints"; echo; }; cat "$UI_SORT_DIR/title"' >"$in/header.sh"
    args+=("--bind=result:+transform:sh $in/header.sh")
    args+=("--bind=resize:+transform:bash -c '. \"\$UI_SORT_LIB\"; ui_sort_step resize'")
    if [[ -s "$in/cells" ]]; then
      # the cut cell under the cursor, whole, under the list; the layout wrote $in/full
      # (key: the row as shown; fields: one per column, empty when not cut). Not in a
      # picker with a footer of its own (the kx lists' status line).
      if (( ! footer )); then
        cat >"$in/footer.sh" <<'FOOTER'
c=$(cut -d' ' -f1 "$UI_SORT_DIR/state"); K="$1" awk -F '\036' -v c="${c:-1}" '$1 == ENVIRON["K"] { print $(c + 1); exit }' "$UI_SORT_DIR/full" 2>/dev/null
FOOTER
        UI_TOAST_CLEAR="transform-footer(bash $in/footer.sh {})"   # a toast gives the footer back to the cut cell
        # (not over a toast: a reload moves the cursor right after the toast is shown)
        # (the + adds to a picker's own focus bind instead of replacing it)
        args+=("--bind=focus:+transform:[ -s \"\$UI_TOAST_DIR/id\" ] || printf 'change-footer:%s' \"\$(bash $in/footer.sh {})\"")
      fi
    fi
    local step="bash -c '. \"\$UI_SORT_LIB\"; ui_sort_step \"\$@\"' _"
    args+=("--bind=click-header:transform:$step click \"\$FZF_CLICK_HEADER_LINE\" \"\$FZF_CLICK_HEADER_COLUMN\""
           "--bind=alt-s:transform:$step sort" "--bind=alt-left:transform:$step left" "--bind=alt-right:transform:$step right"
           "--bind=alt-shift-left:transform:$step mvleft" "--bind=alt-shift-right:transform:$step mvright")
    # ticks stay on their rows through a sort (fzf with --id-nth)
    (( multi )) && fzf --id-nth=1 --filter= </dev/null >/dev/null 2>&1 && args+=(--id-nth=1)
    "${cmd[@]}" "${args[@]}" <"$in/view" || rc=$?
  elif [[ -n "$in" ]]; then "${cmd[@]}" "${args[@]}" <"$in/rows" || rc=$?
  else "${cmd[@]}" "${args[@]}" || rc=$?; fi
  [[ -n "$in" ]] && rm -rf "$in"
  [[ -n "$UI_TOAST_DIR" ]] && rm -rf "$UI_TOAST_DIR"
  return "$rc"
}

# Marks used in every list, right next to the name ("● shop-dev ◆"):
#   ● this terminal   ◆ default (what new terminals start on)   ⚲ pinned to this folder
# The box's right-side label explains them (ui_legend).
ui_mark_here()    { printf '%s' "${C_GREEN}●${C_RESET}"; }
ui_mark_default() { printf '%s' "${C_MAGENTA}◆${C_RESET}"; }
ui_mark_pin()     { printf '%s' "${C_BLUE}⚲${C_RESET}"; }
# ui_legend here default [pin] -> "● this terminal  ◆ default  ⚲ pinned here"
ui_legend() {
  local out="" k
  for k in "$@"; do
    case "$k" in
      here)    out+="$(ui_mark_here) this terminal  " ;;
      default) out+="$(ui_mark_default) default  " ;;
      pin)     out+="$(ui_mark_pin) pinned here  " ;;
    esac
  done
  printf '%s' "${out%  }"
}

NONPROD_PATTERN="${OKCLI_NONPROD_PATTERN:-dev|test|sbx|sandbox|lab|stag|stg|qa|poc}"
is_prod() { ! [[ "$*" =~ $NONPROD_PATTERN ]]; }

env_badge() {
  if is_prod "$@"; then printf '%s' "${C_RED}prod${C_RESET}"
  elif [[ "$*" =~ stag|stg|uat|preprod ]]; then printf '%s' "${C_YELLOW}stage${C_RESET}"
  else printf '%s' "${C_GREEN}dev${C_RESET}"; fi
}
