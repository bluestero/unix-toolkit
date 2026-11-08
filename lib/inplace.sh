# Questions inside a list that stays open (CLAUDE.md: never leave the picker to ask).
# For a ui_fzf list whose keys run callbacks that print fzf actions (hat does this;
# kx has its own, kube/lib/list.sh). Needs fzf 0.63+.
#
# The list keeps its state in a folder, $IP (one file per value: ip_get / ip_set).
#   mode       list (default), confirm, ask, or the list's own modes
#   pending    what the question is for; the list's callback acts on it
#   question   the question, kept for ip_reask
#   saved_q    the filter typed before the question, put back after it
#
#   ip_confirm "<question>" <pending> [y|n]   yes/no: y and n answer, enter takes the
#                                             default (n unless given), esc is no
#   ip_ask "<question>" <pending> [prefill] [prompt]
#                                             typed: on the prompt line, the list stays
#   ip_reask "<why it failed>"                the same question again, the reason on top
#                                             in red, the typed text kept to fix
#   ip_answer <key>                           in confirm mode: yes / no / "" (not an answer)
# In a sortable picker (ui_fzf --sortable) the question's header goes through
# ui_sort_header, so the column titles stay under it.
# A question's actions bind y and n; the list's start should unbind them
# (--bind start:unbind\(y,n\)) and its way back rebind nothing: ip_back does that part.

ip_get() { cat "$IP/$1" 2>/dev/null; }
ip_set() { printf '%s' "$2" >"$IP/$1"; }

# fzf action with a text argument (brackets the text doesn't contain), and + joins
ip_fz() { ui_fz "$@"; }
ip_join() { local IFS=+; printf '%s' "$*"; }

# the header while asking: an optional line on top (a red reason), the question in
# amber (folded to the window), then its keys
ip_header() {   # question keys [line on top]
  local out=""
  [[ -n ${3:-} ]] && out+="$3"$'\n'
  out+=$(fold -s -w $(( ${FZF_COLUMNS:-$(ui_cols)} - 8 )) <<<"$1" | sed "s/^/${C_YELLOW}${C_BOLD}/; s/\$/${C_RESET}/")
  printf '%s\n%s' "$out" "$(ui_keys "$2")"
}

ip_confirm() {   # question pending [default y|n]
  local d=${3:-n} keys clear=""
  # straight after a typed question: its answer leaves the prompt, the list filters again
  [[ $(ip_get mode) == ask ]] && clear="$(ip_fz change-query "")+enable-search"
  ip_set mode confirm; ip_set pending "$2"; ip_set question "$1"; ip_set default "$d"
  if [[ $d == y ]]; then keys="y: yes (enter too) · n: no (esc too)"; else keys="y: yes · n: no (enter, esc too)"; fi
  ip_join "$(ip_fz change-header "$(ui_sort_header "$(ip_header "$1" "$keys")")")" \
    "$(ip_fz change-prompt "${C_YELLOW}y / n? ${C_RESET}")" "rebind(y,n)" "$(ip_fz change-footer " ")" ${clear:+"$clear"}
}

ip_ask() {   # question pending [prefill] [prompt]
  ip_set mode ask; ip_set pending "$2"; ip_set question "$1"
  ip_join "$(ip_fz change-header "$(ui_sort_header "$(ip_header "$1" "enter: ok · esc: cancel")")")" \
    "$(ip_fz change-prompt "${C_YELLOW}${4:-> }${C_RESET}")" disable-search "unbind(y,n)" \
    "$(ip_fz change-query "${3:-}")" "$(ip_fz change-footer " ")"
}

ip_reask() {   # why the answer didn't work
  local keys="enter: ok · esc: cancel"
  [[ $(ip_get mode) == confirm ]] && keys="y: yes · n: no (enter, esc too)"
  ip_fz change-header "$(ui_sort_header "$(ip_header "$(ip_get question)" "$keys" "${C_RED}✗ $1${C_RESET}")")"
}

ip_answer() {   # key → yes / no / nothing
  case $1 in
    y) echo yes ;;
    n|esc) echo no ;;
    enter) [[ $(ip_get default) == y ]] && echo yes || echo no ;;
  esac
}

# the actions every way back to the list shares: y and n type again, the filter
# returns, searching is on (the list's own header, prompt and rows come with it)
ip_back() {
  ip_set mode list; ip_set pending ""
  ip_join "unbind(y,n)" enable-search "$(ip_fz change-query "$(ip_get saved_q)")"
}
