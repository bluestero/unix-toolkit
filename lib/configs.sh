#!/usr/bin/env bash
# tk configs: the apps the toolkit gives its own config (starship, btop, rofi, kitty,
# readline, yazi keys), each switchable between the toolkit's preset, the app's own
# default (no config from the toolkit), what you had before the toolkit, and back
# one step (undo). One list that stays open, like fk looks: enter on an app shows its
# choices in the same list; results go in the footer.
#
# A preset is a link into the repo, so editing the config edits the repo's copy: the
# list calls that "edited preset". Every change first keeps what was there, so undo
# (one step) brings it back, your edits included; leaving an edited preset puts the
# repo's copy back as committed, so tk update and git stay clean.
#
# Your own changes go in a patch instead: your file in ~/.config/work-toolkit/patches, which
# the preset pulls in last (kitty globinclude, rofi @import, readline $include), so it wins.
# starship and btop can't include a file: starship gets the two merged into a file of its own
# (shell/init.sh, lib/toml_patch.py), btop a settings file of its own (bt_build in components.sh).
# The toolkit never writes to it once it is made; anyone can copy someone's patch.
set -uo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
repo=$(cd "$(dirname "$SELF")/.." && pwd)
mode=ask details=0
# shellcheck source=setup.sh
. "$repo/lib/setup.sh"
# shellcheck source=components.sh
. "$repo/lib/components.sh"
# shellcheck source=inplace.sh
. "$repo/lib/inplace.sh"
snap_dir="$orig_dir/configs"   # <id>.last (what was there before the last change) and <id>.kind
patch_dir="$HOME/.config/work-toolkit/patches"   # the presets name this folder; keep them in step

# id|name shown|program it's for|the config|the preset|how it's put in place (link: the file is a
# link to the preset; block: a marked block in your own file; merge: btop's own file, the preset with
# your patch laid over it)|your patch's file in $patch_dir (empty:
# the preset can't take one)|what it is
cfg_table() {
  printf '%s\n' \
    "starship|starship|starship|$ss|$ss_src|link|starship.toml|the prompt" \
    "btop|btop|btop|$bt|$bt_src|merge|btop.conf|system monitor" \
    "rofi|rofi|rofi|$rofi_conf|$rofi_src|link|rofi.rasi|launcher style" \
    "kitty|kitty|kitty|$kc|$kc_src|link|kitty.conf|terminal settings" \
    "readline|readline|bash|$HOME/.inputrc|$inputrc_src|link|inputrc|keys at the bash prompt (~/.inputrc)" \
    "yazi|yazi keys|yazi|$yk_file|$yk_src|block||> and ctrl+backspace in yazi"
}
cfg_row() {   # id → sets id nice app live src kind patch about
  local line; line=$(cfg_table | grep -m1 "^$1|") || return 1
  IFS='|' read -r id nice app live src kind patch about <<<"$line"
  [[ -n $patch ]] && patch="$patch_dir/$patch"
  return 0
}
# your patch has something in it (more than comments)
cfg_patched() { [[ -n $patch && -f $patch ]] && grep -qvE '^[[:space:]]*(#|//|$)' "$patch"; }
# a new patch: what it is, then the preset as comments to start from
cfg_new_patch() {
  local c='#'; [[ $patch == *.rasi ]] && c='//'
  mkdir -p "$patch_dir"
  { printf "%s Your patch for %s: read after the toolkit's preset, so what you set here wins.\n" "$c" "$nice"
    printf '%s The toolkit never changes this file. The preset (%s) is below as comments:\n' "$c" "${src#"$repo"/}"
    printf '%s uncomment a line and change it, or add your own.\n' "$c"
    [[ $patch == *.toml ]] && printf '%s A setting under [a table] needs its [table] line uncommented too.\n' "$c"
    echo
    sed "s|^|$c |" "$src"; } >"$patch"
}
cfg_ids() { local line; while IFS= read -r line; do type -P "$(cut -d'|' -f3 <<<"$line")" >/dev/null && echo "${line%%|*}"; done < <(cfg_table); }

# the preset changed in the repo (no git: never)
cfg_dirty() { git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 && ! git -C "$repo" diff --quiet HEAD -- "$src" 2>/dev/null; }
# the preset as committed, back in the repo
cfg_clean() { [[ $kind != block ]] && cfg_dirty && git -C "$repo" show "HEAD:${src#"$repo"/}" >"$src"; return 0; }

# CS: preset (as committed), edited (the preset, changed), own (your file), default (none)
cfg_state() {
  if [[ $kind == link ]]; then
    if linked "$live" "$src"; then if cfg_dirty; then CS=edited; else CS=preset; fi
    elif [[ -e $live || -L $live ]]; then CS=own
    else CS=default; fi
  elif [[ $kind == merge ]]; then   # btop: its own file; a link is from older installs
    if linked "$live" "$src"; then if cfg_dirty; then CS=edited; else CS=preset; fi
    elif bt_ours; then CS=preset
    elif [[ -f $live && -f $bt_made ]]; then CS=edited   # changed in btop's menu since the toolkit wrote it
    elif [[ -e $live ]]; then CS=own
    else CS=default; fi
  else
    if has_block "$live" "$(<"$src")"; then CS=preset
    elif grep -qxF "$BLOCK_START" "$live" 2>/dev/null; then CS=edited
    else CS=default; fi
  fi
}
cfg_word() {
  case $1 in
    preset)  printf '%s' "${C_GREEN}✓${C_RESET} toolkit preset" ;;
    edited)  printf '%s' "${C_YELLOW}edited preset${C_RESET}" ;;
    own)     printf '%s' "your own file" ;;
    default) printf '%s' "app's default" ;;
  esac
  [[ $1 == preset || $1 == edited ]] && cfg_patched && printf ' + my patch'
  return 0
}

# keep what is there now, for undo: link (the preset's text, edits and all), file, or none
cfg_snap() {
  mkdir -p "$snap_dir"
  if [[ $kind == link ]] && linked "$live" "$src"; then cp "$src" "$snap_dir/$id.last"; echo link >"$snap_dir/$id.kind"
  elif [[ -f $live ]]; then cp "$live" "$snap_dir/$id.last"; echo file >"$snap_dir/$id.kind"
  else rm -f "$snap_dir/$id.last"; echo none >"$snap_dir/$id.kind"; fi
}
# your file from before the toolkit (empty when there was none)
cfg_before() { local o; o=$(original_of "$live"); [[ -n $o && -f $o ]] && printf '%s' "$o"; }

CH_PRE="Toolkit preset"; CH_APP="App's default"; CH_OLD="What you had before"; CH_UND="Undo the last change"
CH_EDT="Edit my patch"; CH_DRP="Drop my patch"; CH_KPT="Keep these changes as my patch"
cfg_choices() {   # what an app can switch to now: choice<TAB>what it does
  cfg_state
  case $CS in
    preset) ;;
    edited) printf '%s\t%s\n' "$CH_PRE" "the toolkit's ${src#"$repo"/} as committed (your edits kept for undo)" ;;
    *)      printf '%s\t%s\n' "$CH_PRE" "the toolkit's ${src#"$repo"/}" ;;
  esac
  if [[ $CS != default ]]; then
    if [[ $kind == link ]]; then printf '%s\t%s\n' "$CH_APP" "no config file: $nice's built-in settings"
    else printf '%s\t%s\n' "$CH_APP" "the toolkit's keys taken out; the rest of ${live/#$HOME/\~} stays"; fi
  fi
  [[ -n $(cfg_before) ]] && printf '%s\t%s\n' "$CH_OLD" "your ${live/#$HOME/\~} from before the toolkit"
  [[ -f $snap_dir/$id.kind ]] && printf '%s\t%s\n' "$CH_UND" "one step back"
  [[ $kind == merge && $CS == edited ]] &&
    printf '%s\t%s\n' "$CH_KPT" "the settings that differ from the preset go in ${patch/#$HOME/\~}, so they stay"
  if [[ -n $patch && ( $CS == preset || $CS == edited ) ]]; then
    if [[ -f $patch ]]; then printf '%s\t%s\n' "$CH_EDT" "your changes on top of the preset, in ${patch/#$HOME/\~}"
    else printf '%s\t%s\n' "$CH_EDT" "start one from the preset: your changes go in ${patch/#$HOME/\~}, the toolkit's file stays as it is"; fi
  fi
  [[ -n $patch && -f $patch ]] && printf '%s\t%s\n' "$CH_DRP" "back to the plain preset (your patch kept as ${patch##*/}.dropped)"
  return 0
}

# cfg_do <choice>: prints the result line (✓ … or ✗ …)
cfg_do() {
  local pick=$1
  setup_phase=install keep_original "$live"   # your own file, kept once (what you had before)
  case $pick in
    "$CH_PRE") cfg_snap; cfg_clean
      case $kind in
        link)  mkdir -p "${live%/*}"; rm -f "$live"; ln -s "$src" "$live" ;;
        merge) bt_build ;;
        block) mkdir -p "${live%/*}"; set_block "$live" "$(<"$src")" ;;
      esac
      echo "✓ $nice: toolkit preset" ;;
    "$CH_APP") cfg_snap; cfg_clean
      if [[ $kind == block ]]; then drop_block "$live"; else rm -f "$live"; fi
      echo "✓ $nice: the app's default" ;;
    "$CH_OLD") local o; o=$(cfg_before); cfg_snap; cfg_clean
      rm -f "$live"; mkdir -p "${live%/*}"; cp -p "$o" "$live"
      echo "✓ $nice: what you had before the toolkit" ;;
    "$CH_UND") cfg_undo ;;
    "$CH_DRP") cfg_snap; mv "$patch" "$patch.dropped"; [[ $kind == merge ]] && bt_build
      echo "✓ $nice: patch dropped (kept as ${patch/#$HOME/\~}.dropped)" ;;
    "$CH_KPT") cfg_keep; echo "✓ $nice: its changes are your patch now (${patch/#$HOME/\~})" ;;
    *) echo "✗ nothing changed"; return 0 ;;
  esac
  cfg_after
}
# undo: what was there before the last change comes back; undo again redoes it
cfg_undo() {
  local k t; k=$(<"$snap_dir/$id.kind"); t=$(mktemp)
  [[ $k == none ]] || cp "$snap_dir/$id.last" "$t"
  cfg_snap
  case $k in
    link) rm -f "$live"; mkdir -p "${live%/*}"; cat "$t" >"$src"; ln -s "$src" "$live" ;;
    file) rm -f "$live"; mkdir -p "${live%/*}"; cat "$t" >"$live" ;;
    none) rm -f "$live" ;;
  esac
  rm -f "$t"
  echo "✓ $nice: back to before the last change"
}
# btop's settings that differ from the preset (and patch), added to the patch; then its file again
cfg_keep() {
  local now t; now=$(bt_kv "$live"); cfg_snap; cfg_clean; t=$(mktemp)
  [[ -f $patch ]] || cfg_new_patch
  comm -23 <(printf '%s\n' "$now") <(bt_merge | bt_kv) >"$t"
  [[ -s $t ]] && { printf '\n# kept from btop (%s)\n' "$(date +%F)"; cat "$t"; } >>"$patch"
  rm -f "$t"; bt_build
}
# starship: your patch merged over the preset (shell/init.sh does the same at start); prints an error
ss_merged="$HOME/.local/state/work-toolkit/starship.toml"
cfg_ss_merge() {
  if [[ -f $patch && -e $live ]]; then python3 -I "$repo/lib/toml_patch.py" "$live" "$patch" "$ss_merged" 2>&1 | sed "s|^$HOME|~|; s|^|✗ starship: your patch has an error: |"
  else rm -f "$ss_merged"; fi
}
# what has to notice the change
cfg_after() {
  local fk; fk=$(layer_path "$repo" feelkit 2>/dev/null)
  case $id in
    starship) cfg_ss_merge >/dev/null   # (an error shows when you edit the patch)
      [[ -x $fk/bin/k-bg ]] && "$fk/bin/k-bg" __sync_prompt >/dev/null 2>&1 ;;   # its accent copy is what starship reads
    kitty) echo "  (kitty: ctrl+shift+f5 reloads it)" ;;
  esac
  return 0
}

# ------------------------------------------------------------------ list ---
cfg_rows() {   # a title row, then app · config · what it is, the id after a TAB
  local i S=$'\x1f' id nice app live src kind patch about
  printf 'APP%sCONFIG%sWHAT IT IS\n' "$S" "$S"
  for i in $(cfg_ids); do cfg_row "$i"; cfg_state; printf '%s\t%s\n' "$nice$S$(cfg_word "$CS")$S$about" "$id"; done
}
cfg_menu_rows() {   # a title row, then choice · what it does, the choice after a TAB
  local c n S=$'\x1f'
  printf 'CHOICE%sWHAT IT DOES\n' "$S"
  cfg_choices | while IFS=$'\t' read -r c n; do printf '%s\t%s\n' "$c$S$n" "$c"; done
}
cfg_lay() { print_table 3 "$(ui_pick_width)" <"$IP/cells.$1" >"$IP/rows.$1"; }
CFG_KEYS="# Pick an app, then which config it uses
enter: choose · esc: close"

cfg_list() {
  [[ -n $(cfg_ids) ]] || die "none of the apps the toolkit configures is installed · see: tk install"
  ui_fzf_at_least 0.63 || die "the list needs fzf 0.63 or newer · ./install.sh fzf"
  IP=$(mktemp -d) || return 1; export IP
  trap 'rm -rf "$IP"' EXIT
  ip_set mode list
  cfg_rows >"$IP/cells.list"; cfg_lay list
  local cb k; cb="bash $(printf %q "$SELF") __key"
  local -a binds=(--bind "start:unbind(y,n)")
  for k in enter esc y n resize; do binds+=(--bind "$k:transform:$cb $k {2} {q}"); done
  ui_fzf 'tk · configs' --toast --with-shell='bash -c' --delimiter='\t' --with-nth=1 --header-lines=1 \
    --prompt='app> ' --footer=' ' --header="$CFG_KEYS" "${binds[@]}" <"$IP/rows.list" >/dev/null
  return 0
}

cfg_relist() { cfg_rows >"$IP/cells.list"; cfg_lay list; cat "$IP/rows.list"; }
cfg_to_list() {   # [toast]: back to the apps, the cursor on the one just changed
  # the rows are made as fzf reloads: after the editor (Edit my patch) they have changed
  local n; n=$(awk -F'\t' -v id="$(ip_get cur)" '$2 == id { print NR - 1; exit }' "$IP/rows.list")
  local -a a=("$(ip_back)" "$(ip_fz reload-sync "bash $(printf %q "$SELF") __relist")" "pos(${n:-1})"
    "$(ip_fz change-header "$(ui_keys "$CFG_KEYS")")" "$(ip_fz change-prompt 'app> ')")
  if [[ -n ${1:-} ]]; then a+=("$(ui_toast "$1")"); else a+=("$(ip_fz change-footer " ")"); fi
  ip_join "${a[@]}"
}
cfg_run() {   # choice → back to the list with the result in the footer
  local out; out=$(cfg_do "$1" 2>&1 | grep -v '^$' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  [[ $out == ✓* ]] || out="✗ ${out:-nothing changed}"
  cfg_to_list "$out"
}

cfg_key() {   # key value query (value: the id in the list, the choice in the menu)
  local k=$1 v=$2 q=$3 m id nice app live src kind patch about
  m=$(ip_get mode)
  if [[ $k == resize ]]; then
    local w=list; [[ $m == list ]] || w=menu
    cfg_lay "$w"; ip_join "$(ip_fz reload-sync "cat $(printf %q "$IP/rows.$w")")" "pos(${FZF_POS:-1})"; return
  fi
  case $m in
    list)
      case $k in
        esc) echo abort ;;
        enter)
          [[ -n $v ]] && cfg_row "$v" || return 0
          ip_set saved_q "$q"; ip_set mode menu; ip_set cur "$id"
          cfg_menu_rows >"$IP/cells.menu"; cfg_lay menu
          cfg_state
          ip_join "$(ip_fz reload-sync "cat $(printf %q "$IP/rows.menu")")" first "$(ip_fz change-query "")" disable-search \
            "$(ip_fz change-header "$(ui_keys "# $nice ($about) now uses: $(strip_ansi "$(cfg_word "$CS")")"$'\n'"enter: switch to it · esc: back")")" \
            "$(ip_fz change-prompt "$nice> ")" "$(ip_fz change-footer " ")" ;;
      esac ;;
    menu)
      cfg_row "$(ip_get cur)"
      case $k in
        esc) cfg_to_list ;;
        enter)
          [[ -n $v ]] || return 0
          if [[ $v == "$CH_EDT" ]]; then   # the editor full screen, then back to the list
            [[ -f $patch ]] || cfg_new_patch
            [[ $kind == merge ]] && cfg_snap   # its file is made again afterwards: undo brings this one back
            ip_join "$(ip_fz execute "${VISUAL:-${EDITOR:-nano}} $(printf %q "$patch")")" \
              "$(ip_fz transform "bash $(printf %q "$SELF") __edited $id")"; return
          fi
          if [[ $v == "$CH_DRP" ]]; then
            ip_set pick "$v"; ip_confirm "Drop your $nice patch? It's kept as ${patch##*/}.dropped." drop n; return
          fi
          cfg_state
          # your own file or your edits would be replaced: ask first (undo still brings them back)
          if [[ $v != "$CH_UND" && ( $CS == own || $CS == edited ) ]]; then
            local what="your own ${live/#$HOME/\~}"
            if [[ $CS == edited && $kind == merge && ! -L $live ]]; then what="the changes made in $nice's menu"
            elif [[ $CS == edited ]]; then what="the uncommitted changes in the repo's ${src#"$repo"/} (yours, or work in progress there)"; fi
            ip_set pick "$v"; ip_confirm "Switch $nice to: $v? This replaces $what (undo brings it back)." switch n; return
          fi
          cfg_run "$v" ;;
      esac ;;
    confirm)
      local a; a=$(ip_answer "$k"); [[ -n $a ]] || return 0
      cfg_row "$(ip_get cur)"
      if [[ $a == yes ]]; then cfg_run "$(ip_get pick)"; else cfg_to_list "Nothing changed"; fi ;;
  esac
}

case "${1:-}" in
  "")    cfg_list ;;
  __key) [[ -z ${NO_COLOR:-} ]] && ui_color; cfg_key "${2:-}" "${3:-}" "${4:-}" ;;
  __relist) [[ -z ${NO_COLOR:-} ]] && ui_color; cfg_relist ;;
  __edited)   # after the editor: what the patch feeds, then back to the list with how it went
    [[ -z ${NO_COLOR:-} ]] && ui_color; cfg_row "${2:-}" || exit 0
    case $id in
      starship) err=$(cfg_ss_merge); fk=$(layer_path "$repo" feelkit 2>/dev/null)
        [[ -x $fk/bin/k-bg ]] && "$fk/bin/k-bg" __sync_prompt >/dev/null 2>&1
        if [[ -n $err ]]; then cfg_to_list "$(head -1 <<<"$err")"
        else cfg_to_list "✓ starship: your patch saved (new terminals pick it up; with feelkit, this one too)"; fi ;;
      btop) bt_build; cfg_to_list "✓ btop: your patch saved (btop reads it when it starts)" ;;
      kitty) cfg_to_list "✓ kitty: your patch saved (ctrl+shift+f5 reloads kitty)" ;;
      *) cfg_to_list "✓ $nice: your patch saved" ;;
    esac ;;
  __refresh)  # shell start, after the preset or the patch changed: btop's file again, unless btop changed it
    cfg_row btop && [[ -f $bt_made && -f $live && ! -L $live ]] &&
      [[ $(sha256sum "$live" | cut -d' ' -f1) == "$(<"$bt_made")" ]] && bt_build ;;
  *)     ui_unknown "tk configs" "$1" ;;
esac
