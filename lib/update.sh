# tk update's view of the parts: install.sh --update=<dir> sources this after lib/components.sh.
# <dir> comes from tk update:
#   before    "id repo state" per part, worked out with the code from before the pull
#   changed   the files the pull changed, full paths
# Each part gets an update state (install.sh's badge shows it), one tab per repo:
#   fix       the pull broke it: was set up and isn't (ticked), was partly and is gone (not ticked),
#             or a link it made points nowhere (ticked)
#   new       a part the pull added (not ticked)
#   removed   a part the pull took away, with links it left pointing nowhere: ticked, it removes them
#   gone      a part the pull took away that left nothing tk can find
#   updated   set up, and the pull changed files it links to: nothing to do
#   current   set up, nothing changed for it
# A part that wasn't set up before and still isn't (and isn't new) isn't shown.

declare -A U_BEFORE=() U_FROM=() U_TOUCHED=() U_GONE=()
preticked=()
while read -r _id _from _st; do U_BEFORE[$_id]=$_st U_FROM[$_id]=$_from; done <"$update/before"
# the parts whose links lead to a file the pull changed (or into a folder with one)
while IFS= read -r _id; do U_TOUCHED[$_id]=1; done < <(link_records |
  awk -F '\t' 'NR == FNR { c[$0] = 1; next }
    $1 != "" { for (f in c) if (f == $3 || index(f, $3 "/") == 1) { print $1; break } }' "$update/changed" -)
unset _id _from _st

# u_dead <id>: "link TAB target" for each link of that part that points nowhere now
# (links no part owns come under old-links)
U_DEAD=$(leftover_links)
u_dead() {
  local p=$1 l t; [[ $p == old-links ]] && p=""
  awk -F '\t' -v p="$p" '$1 == p { print $2 "\t" $3 }' <<<"$U_DEAD" | while IFS=$'\t' read -r l t; do
    [[ -L $l && ! -e $l ]] && printf '%s\t%s\n' "$l" "$t"
  done
}
# u_clean <id>: remove those links, asking for each
u_clean() {
  local l t
  while IFS=$'\t' read -r l t; do
    if ask "Remove ${l/#$HOME/\~}? (it points at ${t/#$HOME/\~}, which is gone)"; then
      rm -f "$l" && ok "removed"; logf "  removed $l (pointed at $t, gone)"
    else skip; fi
  done < <(u_dead "$1")
}

# A part the pull took away (or links no part owns: "old-links") is still a row: it can clean up.
u_retired() {
  local f=${1//-/_}
  eval "label_$f() { echo '$1 (removed)'; }
    title_$f() { echo '${2:-removed upstream}: cleans up what it left'; }
    detail_$f() { u_dead '$1' | cut -f1 | sed \"s#^\$HOME#~#\" | paste -sd ' '; }
    state_$f() { NOTE=''; if u_dead '$1' | grep -q .; then STATE=partial; else STATE=installed; fi; }
    install_$f() { u_clean '$1'; }
    uninstall_$f() { :; }"
  U_GONE[$1]=1; COMPONENTS+=("$1")
  [[ ${U_FROM[$1]:-toolkit} == toolkit ]] || LAYER_OF[$1]=${U_FROM[$1]}
}
for _id in "${!U_BEFORE[@]}"; do
  [[ " ${COMPONENTS[*]} " == *" $_id "* ]] && continue
  [[ ${U_BEFORE[$_id]} == installed || ${U_BEFORE[$_id]} == partial ]] && u_retired "$_id"
done
# links left by a part that's gone (from an older pull, too), or by no part
while IFS= read -r _id; do
  if [[ -z $_id ]]; then u_retired old-links "links the toolkit made"
  elif [[ " ${COMPONENTS[*]} " != *" $_id "* ]]; then u_retired "$_id"; fi
done < <(cut -f1 <<<"$U_DEAD" | sort -u | { [[ -n $U_DEAD ]] && cat; })
unset _id

# Tabs: the toolkit, then each layer
group_of() { repo_of "$1"; }
GROUP_ABOUT[toolkit]="The toolkit's own parts."
for _l in $(printf '%s\n' "${LAYER_OF[@]}" | sort -u); do
  GROUP_ABOUT[$_l]="The $_l layer's parts${STANDALONE[$_l]:+ (on its own: ${STANDALONE[$_l]} install sets it up)}."
done
unset _l

# update_status <id>: after component_state, turns STATE/NOTE into the update state.
# 1 = don't show it. Ticks (preticked) what's safe to do without a second thought.
update_status() {
  local id=$1 b=${U_BEFORE[$1]-} dead
  if [[ -v U_GONE[$id] ]]; then
    if [[ $STATE == partial ]]; then STATE=removed NOTE="$(u_dead "$id" | grep -c .) link(s) it left point nowhere"; preticked+=("$id")
    else STATE=gone NOTE="nothing of it left that tk can find"; fi
    return 0
  fi
  dead=$(u_dead "$id" | cut -f1 | sed "s#^$HOME#~#" | paste -sd ' ')
  if [[ -n $dead ]]; then
    NOTE="points nowhere now: $dead${NOTE:+; $NOTE}"; STATE=fix; preticked+=("$id"); return 0
  fi
  [[ $STATE == unsupported || $STATE == n/a ]] && return 1
  if [[ -z $b ]]; then
    if [[ $STATE == installed ]]; then STATE=current; else STATE=new; fi
    return 0
  fi
  case $STATE in
    installed) if [[ -v U_TOUCHED[$id] ]]; then STATE=updated NOTE="the pull changed its files; nothing to do"; else STATE=current; fi ;;
    partial|missing|needs)   # only when the pull made it worse: no news is no row
      if [[ $b == installed ]]; then preticked+=("$id")
      elif [[ $b != partial || $STATE != missing ]]; then return 1; fi
      STATE=fix ;;
    *) return 1 ;;
  esac
}
