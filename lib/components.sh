# What install.sh / uninstall.sh manage. Sourced after lib/setup.sh.
#
# Each component <id> has:
#   label_<id>       short name (summary at the end)
#   title_<id>       one line in plain words: what you get
#   detail_<id>      what it touches on disk (shown with --details)
#   state_<id>       sets STATE (installed | partial | missing | n/a) and NOTE
#   install_<id>     brings it to "installed"; does nothing if already there
#   uninstall_<id>   puts things back; does nothing if already gone
# (<id> with - replaced by _ in function names)
# Whether this machine can run a component at all (GNOME? apt? Linux?) is checked
# first, from requires_of below; state_<id> only covers what's left (n/a there =
# a dependency such as kitty isn't installed yet).

# shellcheck source=platform.sh
. "$repo/lib/platform.sh"
# shellcheck source=layers.sh
. "$repo/lib/layers.sh"

COMPONENTS=(bash keys commands starship fzf kitty kitty-config kitty-nautilus zsh login-shell btop yazi direnv window-calls alt-tab-desktop hide-docker-tray app-keys rofi okta-aws-cli aws-cli kubectl eks-clusters repos claude-skill claude-hook claude-guidelines)
# Shown in groups in the checklist; the rest are optional extras.
RECOMMENDED=(bash keys commands starship fzf)
KITTY_PARTS=(kitty kitty-config kitty-nautilus)
DESKTOP_PARTS=(window-calls alt-tab-desktop hide-docker-tray app-keys rofi)
# Components with a settings look: naming one that is installed opens the keep / look / defaults menu
LOOK_PARTS=()   # components with a settings menu; a layer adds its own (LOOK_PARTS+=)
WORKSPACE_PARTS=(repos)
CLAUDE_PARTS=(claude-skill claude-hook claude-guidelines)
CLOUD_PARTS=(okta-aws-cli aws-cli kubectl eks-clusters)
# Which repo a component comes from: the toolkit, or the layer that adds it (feelkit, ...).
repo_of() { echo "${LAYER_OF[$1]:-toolkit}"; }
group_of() {
  # a layer's component names its own group (group_<id>)
  if declare -F "$(fn group "$1")" >/dev/null; then "$(fn group "$1")"
  elif [[ " ${RECOMMENDED[*]} " == *" $1 "* ]]; then echo Recommended
  elif [[ " ${KITTY_PARTS[*]} " == *" $1 "* ]]; then echo Kitty
  elif [[ " ${DESKTOP_PARTS[*]} " == *" $1 "* ]]; then echo "Desktop (GNOME)"
  elif [[ " ${CLOUD_PARTS[*]} " == *" $1 "* ]]; then echo Cloud
  elif [[ " ${WORKSPACE_PARTS[*]} " == *" $1 "* ]]; then echo Workspaces
  elif [[ " ${CLAUDE_PARTS[*]} " == *" $1 "* ]]; then echo "Claude Code"
  else echo Optional; fi
}

# What a component needs from the machine itself (see lib/platform.sh). Anything
# not listed works wherever bash does. A component whose needs aren't met gets
# the state "unsupported" with the reason, and is left out of the setup list.
#   linux  Linux-only download or tool        gnome  GNOME session (gsettings, extensions)
#   apt    installs packages with apt
requires_of() {
  # a layer's component names its own needs (requires_<id>)
  if declare -F "$(fn requires "$1")" >/dev/null; then "$(fn requires "$1")"; return; fi
  case "$1" in
    fzf|kitty|login-shell|yazi|direnv|okta-aws-cli|aws-cli|kubectl) echo "linux" ;;
    zsh|btop)                              echo "apt" ;;
    kitty-nautilus|rofi)                   echo "gnome apt" ;;
    window-calls|alt-tab-desktop|hide-docker-tray|app-keys) echo "gnome" ;;
  esac
}
# component_unsupported <id>: the reason this machine can't run it; nothing when it can.
component_unsupported() {
  local need why
  for need in $(requires_of "$1"); do
    why=$(unmet_requirement "$need"); [[ -n $why ]] && { echo "$why"; return 0; }
  done
  return 0
}
# component_state <id>: sets STATE and NOTE (unsupported here, else the component's own check)
component_state() {
  local why; why=$(component_unsupported "$1")
  if [[ -n $why ]]; then STATE=unsupported NOTE=$why; else "$(fn state "$1")"; fi
}

fn() { printf '%s_%s' "$1" "${2//-/_}"; }
ver_lt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

init_line="[ -f \"$repo/shell/init.sh\" ] && . \"$repo/shell/init.sh\"  # work toolkit (okcli, kx, twin, ctx)"
init_re='^\[ -f "[^"]*/shell/init\.sh" \] && \. "[^"]*/shell/init\.sh".*# work toolkit'

# ---------------------------------------------------------------- bash ---
rc="$HOME/.bashrc"
label_bash() { echo "Bash setup"; }
title_bash() { echo "Your work aliases and tools in every bash terminal"; }
detail_bash() { echo "~/.bashrc loads the toolkit with one line; old copies and clashing leftovers removed"; }
bash_plan() {
  BASH_PLAN=$(mktemp)
  python3 -I "$repo/lib/bashrc_plan.py" "$rc" "$init_line" >"$BASH_PLAN"
}
state_bash() {
  NOTE=""
  [[ -f "$rc" ]] || { STATE=missing; NOTE="no ~/.bashrc"; return; }
  bash_plan
  if cmp -s "$rc" "$BASH_PLAN"; then STATE=installed
  elif grep -qE "$init_re" "$rc"; then STATE=partial; NOTE="leftovers to clean up in ~/.bashrc"
  else STATE=missing; fi
  rm -f "$BASH_PLAN"
}
install_bash() {
  local b missing v
  [[ -f "$rc" ]] || touch "$rc"
  bash_plan
  if cmp -s "$rc" "$BASH_PLAN"; then rm -f "$BASH_PLAN"; ok "already done"; return; fi
  say "      ${D}$(diff "$rc" "$BASH_PLAN" | grep -c '^<') lines move out of ~/.bashrc (into shell/common.sh and the tools), $(diff "$rc" "$BASH_PLAN" | grep -c '^>') added${R}"
  logf "--- ~/.bashrc diff ---"
  diff -u "$rc" "$BASH_PLAN" --label "~/.bashrc" --label "~/.bashrc (new)" >>"$log_file"
  (( details )) && diff -u "$rc" "$BASH_PLAN" --label "~/.bashrc" --label "~/.bashrc (new)" | sed 's/^/    /'
  missing=""
  for v in $(grep -oE '^export OKTA_AWSCLI_[A-Z_]+' "$rc" | sed 's/^export //'); do
    cat "$repo/okta/shell/okta-env.sh" "$repo"/layers/*/shell/init.sh 2>/dev/null | grep -q "^export $v=" || missing+="$v "
  done
  [[ -n "$missing" ]] && warn "not in okta/shell/okta-env.sh or a layer yet, so they'd be lost: $missing"
  grep -qE '^[[:space:]]*alias okcli=' "$rc" && warn "an active 'alias okcli=' stays in ~/.bashrc; it would shadow okcli"
  if ask "Update ~/.bashrc?"; then
    b=$(backup "$rc")
    cat "$BASH_PLAN" >"$rc"
    if bash -n "$rc"; then ok "done (backup: ${b/#$HOME/\~})"
    else cp -p "$b" "$rc"; fail "syntax error in the result, so the original was put back"; fi
  else skip "--details shows the diff"; fi
  rm -f "$BASH_PLAN"
}
# Undo: the lines the toolkit took out of your original ~/.bashrc go back where
# they were (lib/bashrc_restore.py), and anything you edited since is kept.
uninstall_bash() {
  local b orig base merged n
  grep -qE "$init_re" "$rc" 2>/dev/null || { ok "not loaded from ~/.bashrc"; return; }
  orig=$(original_of "$rc")
  merged=$(mktemp); base=$(mktemp)
  if [[ -n "$orig" ]] && ! grep -qE "$init_re" "$orig" &&
     python3 -I "$repo/lib/bashrc_plan.py" "$orig" "$init_line" | grep -vE "$init_re" >"$base" &&
     python3 -I "$repo/lib/bashrc_restore.py" <(grep -vE "$init_re" "$rc") "$orig" "$base" >"$merged"; then
    n=$(diff "$rc" "$merged" | grep -c '^>')
    logf "--- ~/.bashrc restore diff ---"; diff -u "$rc" "$merged" --label "~/.bashrc" --label "~/.bashrc (restored)" >>"$log_file"
    if (( n )) && ask "Put back the $n line(s) the toolkit took out of ~/.bashrc? (your edits since are kept; no = only remove the toolkit line)"; then
      b=$(backup "$rc"); cat "$merged" >"$rc"
      if bash -n "$rc"; then ok "removed the toolkit line and put back your $n line(s) (backup: ${b/#$HOME/\~})"
      else cp -p "$b" "$rc"; fail "syntax error after putting them back, so ~/.bashrc is unchanged; your original: ${orig/#$HOME/\~}"; fi
      rm -f "$merged" "$base"; return
    fi
  elif [[ -n "$orig" ]]; then
    warn "couldn't work out what to put back; your pre-toolkit ~/.bashrc: ${orig/#$HOME/\~}"
  fi
  rm -f "$merged" "$base"
  b=$(backup "$rc")
  local tmp; tmp=$(mktemp)
  grep -vE "$init_re" "$rc" | cat -s >"$tmp"; cat "$tmp" >"$rc"; rm -f "$tmp"
  ok "removed the toolkit line (backup: ${b/#$HOME/\~})"
  warn "bash no longer gets the toolkit's aliases, Okta settings, nvm, direnv or starship."
}

# ---------------------------------------------------------------- keys ---
inputrc_src="$repo/shell/inputrc"
label_keys() { echo "Tab & history keys"; }
title_keys() { echo "Smarter Tab completion; ↑/↓ searches history by what you typed"; }
detail_keys() { echo "~/.inputrc for bash (case-insensitive Tab, Up/Down search by what's typed)"; }
state_keys() { NOTE=""; if linked "$HOME/.inputrc" "$inputrc_src"; then STATE=installed; else STATE=missing; fi; }
install_keys() { linked "$HOME/.inputrc" "$inputrc_src" && { ok "already linked"; return; }
  ask "Link ~/.inputrc to shell/inputrc?" && link_file "$HOME/.inputrc" "$inputrc_src" || skip; }
uninstall_keys() { unlink_file "$HOME/.inputrc" "$inputrc_src"; }

# ------------------------------------------------------------ commands ---
cmd_bins=(okta/bin/okcli kube/bin/kx twingate/bin/twin bin/ctx bin/tk ws/bin/ws)
label_commands() { echo "Toolkit commands"; }
title_commands() { echo "tk, okcli, kx, twin, ctx and ws, usable from anywhere"; }
detail_commands() { echo "tk, okcli, kx, twin, ctx, ws in ~/.local/bin (for scripts and other programs)"; }
state_commands() {
  local b n=0
  for b in "${cmd_bins[@]}"; do linked "$HOME/.local/bin/${b##*/}" "$repo/$b" && (( n++ )); done
  NOTE=""
  if (( n == ${#cmd_bins[@]} )); then STATE=installed
  elif (( n )); then STATE=partial; NOTE="$n of ${#cmd_bins[@]} linked"
  else STATE=missing; fi
}
install_commands() {
  local b name
  for b in "${cmd_bins[@]}"; do
    name=${b##*/}
    linked "$HOME/.local/bin/$name" "$repo/$b" && continue
    chmod +x "$repo/$b"
    if ask "Add the ${B}$name${R} command?"; then link_file "$HOME/.local/bin/$name" "$repo/$b"; else skip; fi
  done
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin is not on your PATH" ;; esac
}
uninstall_commands() {
  local b
  for b in "${cmd_bins[@]}"; do
    linked "$HOME/.local/bin/${b##*/}" "$repo/$b" && rm -f "$HOME/.local/bin/${b##*/}" && ok "removed ${b##*/}"
  done
  return 0
}

# ------------------------------------------------------------ starship ---
ss="$HOME/.config/starship.toml"; ss_src="$repo/starship/starship.toml"
label_starship() { echo "Starship prompt"; }
title_starship() { echo "Prompt showing git branch, k8s cluster, AWS profile and PROD warnings"; }
detail_starship() { echo "prompt config (git, python, k8s, AWS profile + expiry, PROD markers); starship itself, latest from GitHub (sha256-checked), in ~/.local/bin if it isn't installed"; }
state_starship() { NOTE=""; if linked "$ss" "$ss_src"; then STATE=installed; else STATE=missing; fi
  command -v starship >/dev/null || { NOTE="starship itself isn't installed"; [[ $STATE == installed ]] && STATE=partial; }; }
install_starship() {
  get_tool starship "the prompt itself" "about 5 MB" fetch_starship
  linked "$ss" "$ss_src" && { ok "already linked"; return; }
  ask "Switch to the toolkit's starship prompt?" && link_file "$ss" "$ss_src" || skip; }
fetch_starship() { local a; case "$(dl_arch)" in amd64) a=x86_64 ;; arm64) a=aarch64 ;; esac
  gh_tool starship/starship "starship-$a-unknown-linux-musl.tar.gz" starship; }
uninstall_starship() { unlink_file "$ss" "$ss_src"; drop_tool starship; }

# ----------------------------------------------------------------- fzf ---
# Every toolkit picker runs on fzf. A current release in ~/.local/bin (ahead of
# apt's on PATH) gives the lists a position counter and k-theme its tabs.
fzf_mine="$HOME/.local/bin/fzf"
fzf_ver() { "${1:-fzf}" --version 2>/dev/null | awk '{print $1}'; }
label_fzf() { echo "fzf (current)"; }
title_fzf() { echo "Newer fzf for every picker: shows where you are (12/426), k-theme's tabs"; }
detail_fzf() { echo "fzf $FZF_VERSION from GitHub (checksum-checked) in ~/.local/bin; apt's fzf, if any, stays as the fallback"; }
state_fzf() {
  local v; v=$(fzf_ver); NOTE=""
  if [[ -z "$v" ]]; then STATE=missing
  elif ver_lt "$v" "$FZF_MIN"; then STATE=partial; NOTE="now: $v (too old for the counter and k-theme tabs)"
  elif [[ -x "$fzf_mine" ]] && ver_lt "$(fzf_ver "$fzf_mine")" "$FZF_VERSION"; then STATE=partial; NOTE="update: $(fzf_ver "$fzf_mine") → $FZF_VERSION"
  else STATE=installed; NOTE="$v"; fi
}
install_fzf() {
  local v; v=$(fzf_ver "$fzf_mine")
  if [[ -n "$v" ]] && ! ver_lt "$v" "$FZF_VERSION"; then ok "fzf $v"; return; fi
  if ask "Download fzf $FZF_VERSION into ~/.local/bin? (about 2 MB, no sudo)"; then
    dry && return
    fetch_fzf && ok "fzf $(fzf_ver "$fzf_mine")" || fail "not installed (see the log)"
  else skip; fi
  case "$(command -v fzf)" in "$fzf_mine"|"") ;; *) warn "$(command -v fzf) comes first on PATH; open a new terminal" ;; esac
}
uninstall_fzf() {
  [[ -e "$fzf_mine" ]] || { ok "not installed"; return 0; }
  rm -f "$fzf_mine"
  if command -v fzf >/dev/null; then ok "removed; back to $(command -v fzf) $(fzf_ver)"
  else ok "removed (no other fzf: pickers fall back to plain lists)"; fi
}

# --------------------------------------------------------------- kitty ---
# The official kitty build in ~/.local/kitty.app (no sudo). Ubuntu's apt kitty
# stays installed as a fallback; uninstalling this goes back to it.
kapp="$HOME/.local/kitty.app"
kapp_bin="$kapp/bin/kitty"
kitty_desktop="$HOME/.local/share/applications/kitty.desktop"
kapp_ver() { [[ -x "$kapp_bin" ]] && "$kapp_bin" --version 2>/dev/null | awk '{print $2}'; }
kapp_arch() { case "$(uname -m)" in x86_64|amd64) echo x86_64 ;; aarch64|arm64) echo arm64 ;; esac; }
# Newest release from GitHub: sets KL_VER KL_URL KL_SHA (empty when offline). Asked once per run.
kitty_latest_info() {
  [[ -n "${KL_DONE:-}" ]] && return
  KL_DONE=1 KL_VER="" KL_URL="" KL_SHA=""
  local out
  out=$(curl -fsS -m 6 https://api.github.com/repos/kovidgoyal/kitty/releases/latest 2>/dev/null |
    python3 -Ic '
import json, sys
r = json.load(sys.stdin); arch = sys.argv[1]; ver = r["tag_name"].lstrip("v")
for a in r["assets"]:
    if a["name"] == f"kitty-{ver}-{arch}.txz" and a.get("digest", "").startswith("sha256:"):
        print(ver, a["browser_download_url"], a["digest"][7:])
' "$(kapp_arch)" 2>/dev/null) || return 0
  read -r KL_VER KL_URL KL_SHA <<<"$out"
}
kapp_desktop_ok() { grep -q "^Exec=$kapp_bin" "$kitty_desktop" 2>/dev/null; }
term_alt() { update-alternatives --query x-terminal-emulator 2>/dev/null | sed -n 's/^Value: //p'; }

label_kitty() { echo "Kitty (latest)"; }
title_kitty() { echo "The kitty terminal itself, latest release (Ubuntu's is years old)"; }
detail_kitty() { echo "official build in ~/.local/kitty.app, kitty/kitten in ~/.local/bin, app menu entry; apt kitty kept as a fallback"; }
state_kitty() {
  NOTE=""
  [[ -n "$(kapp_arch)" ]] || { STATE=n/a; NOTE="no build for $(uname -m)"; return; }
  local v; v=$(kapp_ver)
  if [[ -z "$v" ]]; then
    STATE=missing
    command -v kitty >/dev/null && NOTE="now: $(kitty --version 2>/dev/null | awk '{print $2}') (apt)"
    return
  fi
  kitty_latest_info
  if ! linked "$HOME/.local/bin/kitty" "$kapp_bin" || ! kapp_desktop_ok; then STATE=partial; NOTE="$v, not hooked up everywhere"
  elif [[ -n "$KL_VER" ]] && ver_lt "$v" "$KL_VER"; then STATE=partial; NOTE="update: $v → $KL_VER"
  else STATE=installed; NOTE="$v"; fi
}
install_kitty() {
  local v tmp sum
  v=$(kapp_ver); kitty_latest_info
  if [[ -z "$v" ]] || { [[ -n "$KL_VER" ]] && ver_lt "$v" "$KL_VER"; }; then
    [[ -n "$KL_VER" ]] || { fail "couldn't reach GitHub to find the latest kitty (offline?)"; return 1; }
    if ask "Download kitty $KL_VER${v:+ (you have $v)} into ~/.local/kitty.app? (about 40 MB, no sudo)"; then
      tmp=$(mktemp -d)
      if ! curl -fsSL --retry 2 -o "$tmp/kitty.txz" "$KL_URL" 2>>"$log_file"; then
        rm -rf "$tmp"; fail "download failed (see the log)"; return 1
      fi
      sum=$(sha256sum "$tmp/kitty.txz" | cut -d' ' -f1)
      [[ "$sum" == "$KL_SHA" ]] || { rm -rf "$tmp"; fail "download didn't match GitHub's checksum, so nothing was installed"; return 1; }
      mkdir -p "$tmp/app" && tar xJf "$tmp/kitty.txz" -C "$tmp/app" 2>>"$log_file" &&
        "$tmp/app/bin/kitty" --version >/dev/null 2>&1 || { rm -rf "$tmp"; fail "the download doesn't run on this machine"; return 1; }
      rm -rf "$kapp.old"; [[ -d "$kapp" ]] && mv "$kapp" "$kapp.old"
      mkdir -p "$(dirname "$kapp")" && mv "$tmp/app" "$kapp" && rm -rf "$kapp.old" "$tmp"
      logf "  kitty $KL_VER from $KL_URL (sha256 $KL_SHA)"
      ok "kitty $KL_VER installed (checksum verified)"
    else skip; return 0; fi
  else ok "kitty $v is the latest"; fi

  if ! linked "$HOME/.local/bin/kitty" "$kapp_bin" || ! linked "$HOME/.local/bin/kitten" "$kapp/bin/kitten"; then
    if ask "Use it for the ${B}kitty${R} and ${B}kitten${R} commands? (links in ~/.local/bin)"; then
      link_file "$HOME/.local/bin/kitty" "$kapp_bin"
      link_file "$HOME/.local/bin/kitten" "$kapp/bin/kitten"
    else skip; fi
  fi

  # The app menu / dock entry. A user copy may already exist (kitty-icons keeps the
  # icon you picked there); only its Exec lines change.
  if ! kapp_desktop_ok && ask "Open the new kitty from the app menu and dock?"; then
    mkdir -p "$(dirname "$kitty_desktop")"
    if [[ ! -f "$kitty_desktop" ]]; then
      cp "$kapp/share/applications/kitty.desktop" "$kitty_desktop"
      sed -i "s|^Icon=kitty$|Icon=$kapp/share/icons/hicolor/256x256/apps/kitty.png|" "$kitty_desktop"
    fi
    sed -i -E "s#^(Try)?Exec=kitty( |$)#\1Exec=$kapp_bin\2#" "$kitty_desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$kitty_desktop")" 2>/dev/null
    kapp_desktop_ok && ok "done" || fail "couldn't update $kitty_desktop"
  fi

  # Ctrl+Alt+T and Files' "Open in Terminal" (set up by kitty-nautilus) use this.
  if [[ "$(term_alt)" == /usr/bin/kitty ]] &&
     ask "Make Ctrl+Alt+T and \"Open in Terminal\" use the new kitty too? (needs sudo)"; then
    as_root update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$kapp_bin" 30 >>"$log_file" 2>&1 &&
      as_root update-alternatives --set x-terminal-emulator "$kapp_bin" >>"$log_file" 2>&1 && ok "done" || fail "update-alternatives failed (see the log)"
  fi
  warn "quit kitty fully (every window) and reopen it to start the new version"
}
uninstall_kitty() {
  [[ -d "$kapp" ]] || { ok "not installed"; return 0; }
  if [[ "$(term_alt)" == "$kapp_bin" ]]; then
    if [[ -x /usr/bin/kitty ]]; then as_root update-alternatives --set x-terminal-emulator /usr/bin/kitty >>"$log_file" 2>&1
    else as_root update-alternatives --auto x-terminal-emulator >>"$log_file" 2>&1; fi
  fi
  as_root update-alternatives --remove x-terminal-emulator "$kapp_bin" >>"$log_file" 2>&1 || true
  if [[ -f "$kitty_desktop" ]]; then
    sed -i -E "s#^(Try)?Exec=$kapp_bin#\1Exec=kitty#" "$kitty_desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$kitty_desktop")" 2>/dev/null
  fi
  unlink_file "$HOME/.local/bin/kitty" "$kapp_bin"
  unlink_file "$HOME/.local/bin/kitten" "$kapp/bin/kitten"
  rm -rf "$kapp"
  if [[ -x /usr/bin/kitty ]]; then ok "removed; back to apt's kitty $(/usr/bin/kitty --version | awk '{print $2}') (quit and reopen kitty)"
  else warn "removed, and there's no apt kitty: install one with: sudo apt install kitty"; fi
}

# -------------------------------------------------------- kitty-config ---
kc="$HOME/.config/kitty/kitty.conf"; kc_src="$repo/kitty/kitty.conf"
label_kitty_config() { echo "Kitty settings"; }
title_kitty_config() { echo "Use the toolkit's kitty terminal settings"; }
detail_kitty_config() { echo "~/.config/kitty/kitty.conf from kitty/kitty.conf"; }
state_kitty_config() { NOTE=""
  command -v kitty >/dev/null || { STATE=n/a; NOTE="kitty isn't installed"; return; }
  if linked "$kc" "$kc_src"; then STATE=installed; else STATE=missing; fi; }
install_kitty_config() { linked "$kc" "$kc_src" && { ok "already linked"; return; }
  if [[ -f "$kc" && ! -L "$kc" ]] && ! cmp -s "$kc" "$kc_src"; then
    warn "your current kitty.conf differs from kitty/kitty.conf (it's kept as a backup)"
    (( details )) && diff -u "$kc" "$kc_src" | sed 's/^/    /'
  fi
  ask "Link kitty.conf to the repo copy?" && link_file "$kc" "$kc_src" || skip; }
uninstall_kitty_config() {
  linked "$kc" "$kc_src" || return 0
  rm -f "$kc"
  local b; b=$(latest_backup "$kc")
  if [[ -n "$b" ]]; then mv "$b" "$kc"; ok "unlinked, put back ${b/#$HOME/\~}"
  else cp "$kc_src" "$kc"; ok "unlinked (left a plain copy so kitty keeps its settings)"; fi
}

# ---------------------------------------------------------------- btop ---
# btop with the toolkit's settings (no black panel, rounded boxes). Its colours are
# generated from the kitty theme in use (k-theme writes ~/.config/btop/themes/kitty.theme).
bt="$HOME/.config/btop/btop.conf"; bt_src="$repo/btop/btop.conf"
kth="$(layer_path "$repo" feelkit 2>/dev/null)/bin/k-theme"   # feelkit's; colours follow the theme only when it is there
label_btop() { echo "btop"; }
title_btop() { echo "btop system monitor, set up to follow your kitty colour theme"; }
detail_btop() { echo "btop (apt) if missing; ~/.config/btop/btop.conf -> btop/btop.conf; kitty.theme written by k-theme"; }
state_btop() { NOTE=""
  local n=0
  command -v btop >/dev/null && (( n++ ))
  linked "$bt" "$bt_src" && (( n++ ))
  if (( n == 2 )); then STATE=installed; elif (( n )); then STATE=partial; else STATE=missing; fi; }
install_btop() {
  if ! command -v btop >/dev/null; then
    if ask "Install btop? (apt, needs sudo)"; then
      apt_install btop && ok "installed" || { fail "apt failed (see $log_file)"; return 1; }
    else skip; return 0; fi
  fi
  if ! linked "$bt" "$bt_src"; then
    ask "Use the toolkit's btop settings? (your own are kept as a backup)" && link_file "$bt" "$bt_src" || { skip; return 0; }
  else ok "btop settings already linked"; fi
  if [[ -x $kth ]]; then dry || "$kth" btop >>"$log_file" 2>&1 && ok "colours follow k-theme ${D}(theme: $("$kth" current 2>/dev/null))${R}"
  else ok "colours follow the kitty theme once feelkit is installed"; fi
}
uninstall_btop() {
  rm -f "$HOME/.config/btop/themes/kitty.theme"
  unlink_file "$bt" "$bt_src"
  if command -v btop >/dev/null && ask "Also remove the btop package? (apt, needs sudo)" n; then
    as_root apt-get remove -y btop >>"$log_file" 2>&1 && ok "package removed" || fail "apt failed (see $log_file)"
  fi
}

# ---------------------------------------------------------------- yazi ---
# Terminal file manager (yazi) plus the `y` command (yazi/shell/y.sh) that leaves
# your shell in the folder you quit in. Colours come from the terminal's own
# palette, so it already follows the kitty theme.
yazi_mine="$HOME/.local/bin/yazi"
yazi_ver() { "${1:-yazi}" --version 2>/dev/null | awk '/Version:/ { print $2; exit }'; }
label_yazi() { echo "yazi"; }
title_yazi() { echo "yazi file manager; y opens it and cd's to where you quit"; }
detail_yazi() { echo "yazi $YAZI_VERSION from GitHub (sha256-checked) in ~/.local/bin; the y command comes with the toolkit's shell setup"; }
state_yazi() {
  local v; v=$(yazi_ver); NOTE=""
  if [[ -z "$v" ]]; then STATE=missing
  elif [[ -x "$yazi_mine" ]] && ver_lt "$(yazi_ver "$yazi_mine")" "$YAZI_VERSION"; then STATE=partial; NOTE="update: $(yazi_ver "$yazi_mine") → $YAZI_VERSION"
  else STATE=installed; NOTE="$v"; fi
}
install_yazi() {
  local v; v=$(yazi_ver "$yazi_mine")
  if [[ -n "$v" ]] && ! ver_lt "$v" "$YAZI_VERSION"; then ok "yazi $v"; return; fi
  if [[ -z "$v" ]] && command -v yazi >/dev/null; then ok "yazi $(yazi_ver) is already installed elsewhere"; return; fi
  if ask "Download yazi $YAZI_VERSION into ~/.local/bin? (about 10 MB, no sudo)"; then
    dry && return
    fetch_yazi && ok "yazi $(yazi_ver "$yazi_mine") ${D}(type y; q quits, Q quits without cd)${R}" || fail "not installed (see the log)"
  else skip; fi
}
uninstall_yazi() {
  [[ -e "$yazi_mine" ]] || { ok "not installed"; return 0; }
  rm -f "$yazi_mine" "$HOME/.local/bin/ya"
  ok "removed ${D}(your ~/.config/yazi stays)${R}"
}

# ----------------------------------------------------------------- zsh ---
zsh_pkgs=(zsh zsh-autosuggestions)
zshrc_body="[ -f \"$repo/zsh/zshrc\" ] && . \"$repo/zsh/zshrc\""
# GNOME starts the session through the login shell; zsh doesn't read ~/.profile
# on its own, so flatpak apps and ~/.local/bin would go missing without this.
zprofile_body="[ -f ~/.profile ] && emulate sh -c '. ~/.profile'"
# Debian's /etc/zsh/zshrc runs compinit too; zsh/zshrc does it once, cached.
zshenv_body="skip_global_compinit=1"
label_zsh() { echo "Zsh"; }
title_zsh() { echo "Install zsh with suggestions as you type (same tools as bash)"; }
detail_zsh() { echo "zsh + faded suggestions; ~/.zshrc loads the same toolkit as bash"; }
state_zsh() {
  local n=0 missing
  missing=$(missing_pkgs "${zsh_pkgs[@]}")
  [[ -z "$missing" ]] && (( n++ ))
  has_block "$HOME/.zshrc" "$zshrc_body" && (( n++ ))
  has_block "$HOME/.zprofile" "$zprofile_body" && (( n++ ))
  has_block "$HOME/.zshenv" "$zshenv_body" && (( n++ ))
  NOTE=""
  if (( n == 4 )); then STATE=installed
  elif (( n )); then STATE=partial; NOTE="${missing:+packages missing: $missing}"
  else STATE=missing; fi
}
install_zsh() {
  local missing; missing=$(missing_pkgs "${zsh_pkgs[@]}")
  if [[ -n "$missing" ]]; then
    if ask "Install $missing(apt, needs sudo)?"; then
      apt_install "${zsh_pkgs[@]}" && ok "installed" || { fail "apt failed (see $log_file)"; return 1; }
    else skip; return 0; fi
  fi
  if has_block "$HOME/.zshrc" "$zshrc_body" && has_block "$HOME/.zprofile" "$zprofile_body" &&
     has_block "$HOME/.zshenv" "$zshenv_body"; then ok "zsh config already set up"; return; fi
  if ask "Set up ~/.zshrc, ~/.zprofile and ~/.zshenv (one managed block each)?"; then
    set_block "$HOME/.zshrc" "$zshrc_body"
    set_block "$HOME/.zprofile" "$zprofile_body"
    set_block "$HOME/.zshenv" "$zshenv_body"
    ok "done. Try it now with: ${C}zsh${R}"
  else skip; fi
}
uninstall_zsh() {
  if [[ "$(login_shell)" == */zsh ]]; then
    warn "zsh is your login shell; switching back to bash first"
    uninstall_login_shell || return 1
  fi
  drop_block "$HOME/.zshrc"; drop_block "$HOME/.zprofile"; drop_block "$HOME/.zshenv"
  ok "removed the toolkit from ~/.zshrc, ~/.zprofile, ~/.zshenv"
  local have=""; pkg_installed zsh && have=1
  if [[ -n "$have" ]] && ask "Also remove the zsh packages (apt, needs sudo)?" n; then
    as_root apt-get remove -y "${zsh_pkgs[@]}" >>"$log_file" 2>&1 && ok "packages removed" || fail "apt failed (see $log_file)"
  fi
}

# --------------------------------------------------------- login-shell ---
login_shell() { getent passwd "$USER" | cut -d: -f7; }
label_login_shell() { echo "Zsh as default"; }
title_login_shell() { echo "Open new terminals in zsh (log out once afterwards)"; }
detail_login_shell() { echo "make zsh your default shell (new terminals; log out once for GNOME)"; }
state_login_shell() { NOTE=""
  command -v zsh >/dev/null || { STATE=n/a; NOTE="needs zsh first"; return; }
  if [[ "$(login_shell)" == */zsh ]]; then STATE=installed; else STATE=missing; NOTE="now: $(login_shell)"; fi; }
install_login_shell() {
  local z; z=$(command -v zsh) || { skip "zsh isn't installed"; return; }
  [[ "$(login_shell)" == "$z" ]] && { ok "already zsh"; return; }
  if ask "Make zsh your login shell (chsh asks for your password)?"; then
    remember_setting login-shell "$(login_shell)"
    chsh -s "$z" && ok "done. Log out and back in so GNOME and kitty pick it up" || fail "chsh failed"
  else skip; fi
}
uninstall_login_shell() {   # back to the shell you had before (bash if unknown)
  local prev; prev=$(recall_setting login-shell)
  [[ -n "$prev" && "$prev" != */zsh && -x "$prev" ]] || prev=/bin/bash
  [[ "$(login_shell)" == "$prev" ]] && { ok "already $prev"; forget_setting login-shell; return 0; }
  chsh -s "$prev" && { forget_setting login-shell; ok "login shell is ${prev##*/} again (log out and back in)"; } || { fail "chsh failed"; return 1; }
}

# ------------------------------------------------------ kitty-nautilus ---
nat_ext="$HOME/.local/share/nautilus-python/extensions/nautilus_open_any_terminal.py"
nat_schema="com.github.stunkymonkey.nautilus-open-any-terminal"
label_kitty_nautilus() { echo "Kitty in Files"; }
title_kitty_nautilus() { echo "Make kitty the default terminal and add \"Open in Terminal\" to Files"; }
detail_kitty_nautilus() { echo "kitty as default terminal, 'Open in Terminal' in Files"; }
state_kitty_nautilus() { NOTE=""
  command -v kitty >/dev/null && command -v nautilus >/dev/null || { STATE=n/a; NOTE="needs kitty and nautilus"; return; }
  local n=0
  [[ -f "$nat_ext" ]] && (( n++ ))
  [[ "$(gsettings get "$nat_schema" terminal 2>/dev/null)" == "'kitty'" ]] && (( n++ ))
  [[ "$(term_alt)" == /usr/bin/kitty || "$(term_alt)" == "$kapp_bin" ]] && (( n++ ))
  if (( n == 3 )); then STATE=installed; elif (( n )); then STATE=partial; else STATE=missing; fi; }
install_kitty_nautilus() { ask "Run kitty/install-kitty-gnome.sh (may need sudo)?" && bash "$repo/kitty/install-kitty-gnome.sh" || skip; }
uninstall_kitty_nautilus() { bash "$repo/kitty/uninstall-kitty-gnome.sh"; }

# ------------------------------------------------------------- looks ---
# A "look" is a preset of an extension's settings (gnome/<name>/settings.dconf, a dconf dump).
# Installing asks whether to use it; the settings from before are kept once and the uninstall
# offers them back, or the app's own defaults (dconf reset).
# look_applied PATH FILE [IGNORE]: every setting in FILE is the same live (keys matching the
# IGNORE regex are skipped: Dash to Panel stores panel keys per monitor).
look_applied() {
  python3 -I - "${3:-}" <(dconf dump "$1" 2>/dev/null) <(sed "s#@REPO@#$repo#; s#@HERE@#$(dirname "$2")#" "$2") <<'PY'
import re, sys
ign = re.compile(sys.argv[1] or r"(?!)")
def parse(p):
    d, sec = {}, ""
    for line in open(p):
        line = line.rstrip("\n")
        if line.startswith("["): sec = line
        elif "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1); d[(sec, k)] = v
    return d
live, want = parse(sys.argv[2]), parse(sys.argv[3])
sys.exit(0 if all(live.get(k) == v for k, v in want.items() if not ign.match(k[1])) else 1)
PY
}
look_apply() {   # look_apply PATH FILE NAME
  mkdir -p "$orig_dir"
  [[ -f "$orig_dir/$3.dconf" ]] || dconf dump "$1" >"$orig_dir/$3.dconf" 2>/dev/null
  sed "s#@REPO@#$repo#; s#@HERE@#$(dirname "$2")#" "$2" | dconf load "$1"
}
look_reset() {   # look_reset PATH NAME: the app's defaults, or your settings from before the toolkit
  dry && return 0
  local f="$orig_dir/$2.dconf"
  dconf reset -f "$1"
  if grep -q = "$f" 2>/dev/null && ask "Put your own earlier $2 settings back? (No: the app's own defaults)"; then
    dconf load "$1" <"$f" && ok "your earlier settings are back"
  else ok "$2 settings back to the app's defaults"; fi
  rm -f "$f" "$orig_dir/$2.last.dconf"
}
# look_menu PATH FILE NAME NICE [IGNORE]: what to do with the settings of an extension that
# is already installed: keep, re-apply the toolkit look, reset to the app's defaults, or (when
# a copy exists) undo the last change. The settings from just before a change are kept once.
look_menu() {
  local path=$1 file=$2 name=$3 nice=$4 ign=${5:-} last="$orig_dir/$3.last.dconf" state pick q rows
  local keep="Keep my settings" app="Re-apply the toolkit look" rst="Reset to the app's defaults" und="Undo the last change"
  if look_applied "$path" "$file" "$ign"; then state="match the toolkit look"; else state="differ from the toolkit look"; fi
  case "$mode" in
    dry) say "  ${C}?${R} $nice settings $state ${D}(dry run: not asked)${R}"; return 0 ;;
    yes) look_applied "$path" "$file" "$ign" && { ok "look already applied"; return 0; }; pick=$app ;;
    *)
      if ! command -v fzf >/dev/null || [[ ! -t 0 ]]; then ok "$nice settings kept"; return 0; fi
      rows="$keep"$'
'"$app"$'
'"$rst"; [[ -f $last ]] && rows+=$'
'"$und"
      q="${C_BOLD}$nice settings $state${C_RESET}"
      pick=$(printf '%s
' "$rows" | ui_fzf "${UI_CONFIRM_LABEL:-settings}" --height=~60% --info=hidden         --no-separator --prompt='  ' --header="$q") || pick=$keep ;;
  esac
  case "$pick" in
    "$app") mkdir -p "$orig_dir"; dconf dump "$path" >"$last" 2>/dev/null
            look_apply "$path" "$file" "$name" && ok "$nice look applied ${D}(the menu can undo it)${R}" ;;
    "$rst") ask "Reset $nice to the app's defaults? (the menu can undo it)" n || { skip; return 0; }
            mkdir -p "$orig_dir"; dconf dump "$path" >"$last" 2>/dev/null
            dconf reset -f "$path" && ok "$nice settings back to the app's defaults ${D}(the menu can undo it)${R}" ;;
    "$und") dconf reset -f "$path"; dconf load "$path" <"$last" && rm -f "$last" && ok "$nice settings back to before the last change" ;;
    *) ok "$nice settings kept" ;;
  esac
}
# A GNOME extension from extensions.gnome.org plus its look. gx_state UUID PATH FILE [IGNORE];
# gx_install UUID NAME PATH FILE [IGNORE]
gx_present() { [[ -d "$HOME/.local/share/gnome-shell/extensions/$1" ]]; }
gx_enabled() { gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q "'$1'"; }
gx_state() {
  NOTE=""
  if gx_present "$1" && gx_enabled "$1"; then
    if look_applied "$2" "$3" "${4:-}"; then STATE=installed; else STATE=partial; NOTE="settings differ from the toolkit's look"; fi
  elif gx_present "$1" || gx_enabled "$1"; then STATE=partial; NOTE="installed, not enabled"
  else STATE=missing; fi
}
gx_install() {
  local uuid=$1 name=$2
  if gx_present "$uuid" && gx_enabled "$uuid"; then look_menu "$3" "$4" "$uuid" "$name" "${5:-}"; return; fi
  if ! gx_present "$uuid"; then
    ask "Download $name from extensions.gnome.org and install it?" || { skip; return 0; }
    ext_download "$uuid" "$name" || return 1
  fi
  if ! gx_enabled "$uuid"; then
    dry || ext_list add "$uuid"
    ok "enabled"; warn "log out and back in once (Wayland loads new extensions only at login)"
  fi
  if look_applied "$3" "$4" "${5:-}"; then ok "look already applied"
  elif ask "Use the toolkit's look for $name? (your current settings are kept for the uninstall)"; then
    look_apply "$3" "$4" "$uuid" && ok "look applied"
  else skip "keeping your settings"; fi
}
gx_uninstall() {
  gx_present "$1" || { ok "not installed"; return; }
  ext_list del "$1"
  gnome-extensions disable "$1" >/dev/null 2>&1
  gnome-extensions uninstall "$1" >/dev/null 2>&1 || rm -rf "$HOME/.local/share/gnome-shell/extensions/$1"
  ok "$2 removed"
  look_reset "$3" "$1"
}

# ---------------------------------------------------- extension helpers ---
ext_is_on() { gnome-extensions list --enabled 2>/dev/null | grep -qx "$1"; }
# ext_download UUID NAME: fetch the release for this GNOME from extensions.gnome.org and install it
ext_download() {
  local ver url tmp
  ver=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
  url=$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$1&shell_version=$ver" |
    python3 -Ic 'import json,sys; print(json.load(sys.stdin)["download_url"])' 2>/dev/null)
  [[ -n "$url" ]] || { fail "no $2 release for GNOME $ver"; return 1; }
  tmp=$(mktemp --suffix=.zip)
  if curl -fsSL -o "$tmp" "https://extensions.gnome.org$url" && gnome-extensions install --force "$tmp" >>"$log_file" 2>&1; then
    ok "installed"; logf "  from https://extensions.gnome.org$url"
  else rm -f "$tmp"; fail "download or install failed (see the log)"; return 1; fi
  rm -f "$tmp"
}
# The launcher entry (gives rofi's window an icon in a dock or panel); shared by rofi and feelkit's docks
launcher_icon_dir="$HOME/.local/share/icons/hicolor/512x512/apps"; launcher_icon="$launcher_icon_dir/k-launch.png"
# feelkit (and any layer) can ask to keep it by defining feelkit_wants_launcher_entry
launcher_entry_wanted() { kb_has rofi-launcher || { declare -F feelkit_wants_launcher_entry >/dev/null && feelkit_wants_launcher_entry; }; }
remove_launcher_entry() {
  launcher_entry_wanted && return 0
  rm -f "$HOME/.local/share/applications/k-launch.desktop" "$launcher_icon" "$HOME/.local/share/icons/hicolor/scalable/apps/k-launch.svg"
}
install_launcher_entry() {
  mkdir -p "$launcher_icon_dir" "$HOME/.local/share/applications"
  convert "$repo/rofi/rofi-icon.png" -resize 512x512 "$launcher_icon" 2>>"$log_file" ||
    install -m 644 "$repo/rofi/rofi-icon.png" "$launcher_icon"
  printf '%s\n' "[Desktop Entry]" "Type=Application" "Name=Launcher" "Comment=App launcher (Alt+Space)" \
    "Exec=$repo/rofi/bin/k-launch apps" "Icon=k-launch" "Terminal=false" "Categories=Utility;" "StartupWMClass=Rofi" \
    >"$HOME/.local/share/applications/k-launch.desktop"
}

# -------------------------------------------------------- window-calls ---
# GNOME extension that lets scripts list, focus and close windows over D-Bus.
# ws uses it to close a workspace's window and to read open windows exactly.
wc_uuid="window-calls@domandoman.xyz"
wc_enabled() { gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q "'$wc_uuid'"; }
wc_present() { [[ -d "$HOME/.local/share/gnome-shell/extensions/$wc_uuid" ]]; }
wc_live() { gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell/Extensions/Windows \
  --method org.gnome.Shell.Extensions.Windows.List >/dev/null 2>&1; }
label_window_calls() { echo "Window Calls"; }
title_window_calls() { echo "Let ws close and focus editor windows (GNOME extension; log out once)"; }
detail_window_calls() { echo "GNOME extension $wc_uuid from extensions.gnome.org into ~/.local/share/gnome-shell/extensions"; }
state_window_calls() {
  NOTE=""
  command -v gnome-shell >/dev/null || { STATE=n/a; NOTE="needs GNOME"; return; }
  if wc_present && wc_enabled; then
    if wc_live; then STATE=installed; else STATE=partial; NOTE="log out and back in to load it"; fi
  elif wc_present; then STATE=partial; NOTE="installed, not enabled"
  else STATE=missing; fi
}
install_window_calls() {
  local ver url tmp
  if wc_present && wc_enabled; then
    wc_live && ok "already active" || ok "installed; log out and back in once to load it"
    return
  fi
  if ! wc_present; then
    ask "Download Window Calls from extensions.gnome.org and install it?" || { skip; return; }
    ver=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
    url=$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$wc_uuid&shell_version=$ver" |
      python3 -Ic 'import json,sys; print(json.load(sys.stdin)["download_url"])' 2>/dev/null)
    [[ -n "$url" ]] || { fail "no Window Calls release for GNOME $ver"; return; }
    tmp=$(mktemp --suffix=.zip)
    if curl -fsSL -o "$tmp" "https://extensions.gnome.org$url" && gnome-extensions install --force "$tmp" >>"$log_file" 2>&1; then
      ok "installed"; logf "  from https://extensions.gnome.org$url"
    else rm -f "$tmp"; fail "download or install failed (see the log)"; return; fi
    rm -f "$tmp"
  fi
  # `gnome-extensions enable` can't see it until GNOME reloads, so add it to the list directly.
  python3 -I - "$wc_uuid" <<'PY'
import ast, subprocess, sys
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
lst = ast.literal_eval(cur.removeprefix("@as ")) if cur else []
if sys.argv[1] not in lst:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(lst + [sys.argv[1]])], check=True)
PY
  ok "enabled"
  warn "log out and back in once (Wayland loads new extensions only at login)"
}
uninstall_window_calls() {
  wc_present || { ok "not installed"; return; }
  gnome-extensions disable "$wc_uuid" >/dev/null 2>&1
  python3 -I - "$wc_uuid" <<'PY'
import ast, subprocess, sys
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
lst = ast.literal_eval(cur.removeprefix("@as ")) if cur else []
if sys.argv[1] in lst:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str([x for x in lst if x != sys.argv[1]])], check=True)
PY
  if gnome-extensions uninstall "$wc_uuid" >/dev/null 2>&1 || rm -rf "$HOME/.local/share/gnome-shell/extensions/$wc_uuid"; then
    ok "removed (ws close stops working; everything else in ws stays)"
  fi
}

# ------------------------------------------------------ alt-tab-desktop ---
# After Super+D (show desktop), Alt+Tab goes back to the window you minimized,
# not the one before it. Small GNOME extension kept in gnome/ and linked in.
atd_uuid="alt-tab-desktop@work-toolkit"
atd_dir="$HOME/.local/share/gnome-shell/extensions/$atd_uuid"; atd_src="$repo/gnome/$atd_uuid"
atd_enabled() { gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q "'$atd_uuid'"; }
ext_list() { # ext_list add|del UUID: edit GNOME's list of enabled extensions
  # add also takes the extension off GNOME's disabled list, which wins over the enabled one
  # (an earlier uninstall puts it there)
  python3 -I -c '
import ast, subprocess, sys
def get(key):
    cur = subprocess.run(["gsettings", "get", "org.gnome.shell", key], capture_output=True, text=True).stdout.strip()
    return ast.literal_eval(cur.removeprefix("@as ")) if cur else []
def put(key, value):
    subprocess.run(["gsettings", "set", "org.gnome.shell", key, str(value)], check=True)
op, uuid = sys.argv[1], sys.argv[2]
lst = get("enabled-extensions")
new = lst + [uuid] if op == "add" and uuid not in lst else [x for x in lst if not (op == "del" and x == uuid)]
if new != lst:
    put("enabled-extensions", new)
if op == "add":
    off = get("disabled-extensions")
    if uuid in off:
        put("disabled-extensions", [x for x in off if x != uuid])
' "$1" "$2"
}
label_alt_tab_desktop() { echo "Alt+Tab after Show Desktop"; }
title_alt_tab_desktop() { echo "After Super+D, Alt+Tab returns to the window you minimized (GNOME extension; log out once)"; }
detail_alt_tab_desktop() { echo "~/.local/share/gnome-shell/extensions/$atd_uuid -> gnome/$atd_uuid, added to enabled extensions"; }
state_alt_tab_desktop() { NOTE=""
  command -v gnome-shell >/dev/null || { STATE=n/a; NOTE="needs GNOME"; return; }
  if linked "$atd_dir" "$atd_src" && atd_enabled; then STATE=installed
  elif linked "$atd_dir" "$atd_src" || atd_enabled; then STATE=partial
  else STATE=missing; fi; }
install_alt_tab_desktop() {
  if linked "$atd_dir" "$atd_src" && atd_enabled; then ok "already installed"; return; fi
  ask "Make Alt+Tab return to the window you minimized with Super+D?" || { skip; return; }
  mkdir -p "$(dirname "$atd_dir")"
  linked "$atd_dir" "$atd_src" || link_file "$atd_dir" "$atd_src" || return 1
  ext_list add "$atd_uuid" && ok "enabled"
  warn "log out and back in once (Wayland loads new extensions only at login)"
}
uninstall_alt_tab_desktop() {
  ext_list del "$atd_uuid"
  unlink_file "$atd_dir" "$atd_src"
}

# ------------------------------------------------------ hide-docker-tray ---
# Docker Desktop's tray item has no icon and an empty menu: three dots that do nothing on click.
# Small GNOME extension (gnome/hide-docker-tray@work-toolkit), linked in, that keeps it hidden.
hdt_uuid="hide-docker-tray@work-toolkit"
hdt_dir="$HOME/.local/share/gnome-shell/extensions/$hdt_uuid"; hdt_src="$repo/gnome/$hdt_uuid"
hdt_enabled() { gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q "'$hdt_uuid'"; }
label_hide_docker_tray() { echo "Hide Docker's tray dots"; }
title_hide_docker_tray() { echo "hides Docker Desktop's dead three-dots tray icon (GNOME extension; log out once)"; }
detail_hide_docker_tray() { echo "~/.local/share/gnome-shell/extensions/$hdt_uuid -> gnome/$hdt_uuid, added to enabled extensions"; }
state_hide_docker_tray() { NOTE=""
  command -v gnome-shell >/dev/null || { STATE=n/a; NOTE="needs GNOME"; return; }
  if linked "$hdt_dir" "$hdt_src" && hdt_enabled; then STATE=installed
  elif linked "$hdt_dir" "$hdt_src" || hdt_enabled; then STATE=partial
  else STATE=missing; fi; }
install_hide_docker_tray() {
  if linked "$hdt_dir" "$hdt_src" && hdt_enabled; then ok "already installed"; return; fi
  ask "Hide Docker Desktop's dead three-dots tray icon?" || { skip; return; }
  mkdir -p "$(dirname "$hdt_dir")"
  linked "$hdt_dir" "$hdt_src" || link_file "$hdt_dir" "$hdt_src" || return 1
  ext_list add "$hdt_uuid" && ok "enabled"
  warn "log out and back in once (Wayland loads new extensions only at login)"
}
uninstall_hide_docker_tray() {
  ext_list del "$hdt_uuid"
  unlink_file "$hdt_dir" "$hdt_src"
}

# ---------------------------------------------------------------- rofi ---
# Rofi as the app launcher: Alt+Space apps (Tab for ssh, windows, run), Alt+Shift+Space ssh.
# Rofi 1.7 is an X11 program; -normal-window (set by rofi/bin/k-launch) lets it take the keyboard on GNOME's Wayland.
rofi_conf="$HOME/.config/rofi/config.rasi"; rofi_src="$repo/rofi/config.rasi"
kb_base=/org/gnome/settings-daemon/plugins/media-keys
kb_root=org.gnome.settings-daemon.plugins.media-keys
kb_schema=$kb_root.custom-keybinding
kb_set() { # kb_set ID NAME COMMAND BINDING
  local path="$kb_base/custom-keybindings/$1/" cur
  gsettings set "$kb_schema:$path" name "$2"; gsettings set "$kb_schema:$path" command "$3"; gsettings set "$kb_schema:$path" binding "$4"
  cur=$(gsettings get $kb_root custom-keybindings)
  [[ "$cur" == *"'$path'"* ]] && return 0
  if [[ "$cur" == *"[]"* ]]; then cur="['$path']"; else cur="${cur%]}, '$path']"; fi
  gsettings set $kb_root custom-keybindings "$cur"
}
kb_has() { gsettings get $kb_root custom-keybindings | grep -q "'$kb_base/custom-keybindings/$1/'"; }
kb_del() {
  local path="$kb_base/custom-keybindings/$1/" cur
  cur=$(gsettings get $kb_root custom-keybindings)
  cur=$(python3 -I -c 'import ast,sys; print([x for x in ast.literal_eval(sys.argv[1].removeprefix("@as ")) if x != sys.argv[2]])' "$cur" "$path")
  gsettings set $kb_root custom-keybindings "$cur"; dconf reset -f "$path"
}
label_rofi() { echo "Rofi launcher"; }
title_rofi() { echo "Alt+Space opens an app launcher (Alt+Shift+Space ssh, Super+X power menu, Super+S speaker/mic/wifi/bluetooth), styled like kitty"; }
detail_rofi() { echo "rofi (apt) if missing; ~/.config/rofi/config.rasi -> rofi/config.rasi; four GNOME shortcuts (Alt+Space, Alt+Shift+Space, Super+X, Super+S); launcher icon (rofi/rofi-icon.png) in the app list and dock"; }
state_rofi() { NOTE=""
  command -v gsettings >/dev/null || { STATE=n/a; NOTE="needs GNOME"; return; }
  local n=0
  command -v rofi >/dev/null && (( n++ ))
  linked "$rofi_conf" "$rofi_src" && (( n++ ))
  kb_has rofi-launcher && kb_has rofi-ssh && kb_has rofi-power && kb_has rofi-devices && (( n++ ))
  [[ -f "$launcher_icon" && -f "$HOME/.local/share/applications/k-launch.desktop" ]] && (( n++ ))
  if (( n == 4 )); then STATE=installed; elif (( n )); then STATE=partial; else STATE=missing; fi; }
install_rofi() {
  if ! command -v rofi >/dev/null; then
    if ask "Install rofi? (apt, needs sudo)"; then
      apt_install rofi && ok "installed" || { fail "apt failed (see $log_file)"; return 1; }
    else skip; return 0; fi
  fi
  if linked "$rofi_conf" "$rofi_src"; then ok "rofi style already linked"
  else ask "Use the toolkit's rofi style? (your own is kept as a backup)" && link_file "$rofi_conf" "$rofi_src" || { skip; return 0; }; fi
  local k_rofi; k_rofi="$(layer_path "$repo" feelkit 2>/dev/null)/bin/k-rofi"
  if [[ -x $k_rofi ]]; then dry || "$k_rofi" >>"$log_file" 2>&1 && ok "colours follow k-theme and k-bg"
  elif [[ ! -e ${rofi_conf%/*}/colors.rasi ]]; then dry || cp "$repo/rofi/colors-default.rasi" "${rofi_conf%/*}/colors.rasi" && ok "default colours (feelkit makes them follow the kitty theme)"; fi
  if [[ -f "$launcher_icon" ]]; then ok "launcher icon already installed"
  else dry || install_launcher_entry && ok "launcher icon installed (log out and back in if the dock still shows none)"; fi
  if kb_has rofi-launcher && kb_has rofi-ssh && kb_has rofi-power && kb_has rofi-devices; then ok "shortcuts already set"
  elif ask "Set Alt+Space (apps), Alt+Shift+Space (ssh), Super+X (power menu) and Super+S (speaker, mic, wifi, bluetooth)?"; then
    kb_set rofi-launcher "Rofi launcher" "$repo/rofi/bin/k-launch apps" "<Alt>space"
    kb_set rofi-ssh "Rofi ssh" "$repo/rofi/bin/k-launch ssh" "<Alt><Shift>space"
    kb_set rofi-power "Rofi power" "$repo/rofi/bin/k-launch power" "<Super>x"
    kb_set rofi-devices "Rofi speaker, mic, wifi, bluetooth" "$repo/rofi/bin/k-launch settings" "<Super>s"
    ok "Alt+Space = apps, Alt+Shift+Space = ssh, Super+X = power menu, Super+S = speaker/mic/wifi/bluetooth"
  else skip; fi
}
uninstall_rofi() {
  kb_has rofi-launcher && kb_del rofi-launcher
  kb_has rofi-ssh && kb_del rofi-ssh
  kb_has rofi-power && kb_del rofi-power
  kb_has rofi-devices && kb_del rofi-devices
  unlink_file "$rofi_conf" "$rofi_src"
  rm -f "${rofi_conf%/*}/colors.rasi"
  remove_launcher_entry
  if command -v rofi >/dev/null && ask "Also remove the rofi package? (apt, needs sudo)" n; then
    as_root apt-get remove -y rofi >>"$log_file" 2>&1 && ok "package removed" || fail "apt failed (see $log_file)"
  fi
}

# ------------------------------------------------------------ app-keys ---
# Super+1..9 = the Nth pinned app in the dock: launch it, bring it to the front, or (when it
# is already in front) minimize it. bin/k-appkey does the work, one short process per key press;
# it uses Window Calls to find and minimize windows. GNOME's own Super+1..9 is switched off
# while this is on (the two would clash) and comes back with the uninstall.
ak_n=(1 2 3 4 5 6 7 8 9)
ak_keys_on() { local i; for i in "${ak_n[@]}"; do kb_has "app-key-$i" || return 1; done; }
ak_native_off() { [[ "$(gsettings get org.gnome.shell.keybindings switch-to-application-1)" == "@as []" ]]; }
label_app_keys() { echo "Super+number app keys"; }
title_app_keys() { echo "Super+1..9 launches, raises or minimizes the Nth dock app (needs Window Calls; replaces GNOME's own)"; }
detail_app_keys() { echo "nine GNOME shortcuts (Super+1..9) running bin/k-appkey; GNOME's switch-to-application keys turned off (put back by the uninstall)"; }
state_app_keys() { NOTE=""
  command -v gsettings >/dev/null || { STATE=n/a; NOTE="needs GNOME"; return; }
  if ak_keys_on && ak_native_off; then STATE=installed
  elif ak_keys_on || ak_native_off; then STATE=partial
  else STATE=missing; fi; }
install_app_keys() {
  local i
  if ak_keys_on && ak_native_off; then ok "already set"; return; fi
  ask "Make Super+1..9 launch, raise or minimize the Nth dock app?" n || { skip; return; }
  wc_live || warn "Window Calls isn't active yet: until it is, Super+number only launches / raises (install it, then log out once)"
  chmod +x "$repo/bin/k-appkey"
  remember_setting app-keys-native "$(gsettings get org.gnome.shell.keybindings switch-to-application-1)"
  for i in "${ak_n[@]}"; do gsettings set org.gnome.shell.keybindings "switch-to-application-$i" "[]"; done
  for i in "${ak_n[@]}"; do kb_set "app-key-$i" "App key $i" "$repo/bin/k-appkey $i" "<Super>$i"; done
  ok "Super+1..9 set (the keys work right away)"
}
uninstall_app_keys() {
  local i
  for i in "${ak_n[@]}"; do kb_has "app-key-$i" && kb_del "app-key-$i"; done
  if [[ -n "$(recall_setting app-keys-native)" ]]; then
    for i in "${ak_n[@]}"; do gsettings reset org.gnome.shell.keybindings "switch-to-application-$i"; done
    forget_setting app-keys-native
    ok "GNOME's own Super+1..9 back"
  fi
}

# ----------------------------------------------- what the tools run on ---
# okta-aws-cli and the AWS CLI (okcli), kubectl (kx), direnv (okcli pin), starship
# (the prompt): the newest release for this CPU, in ~/.local (no sudo). One that's
# already installed some other way (apt, brew, by hand) counts and is left alone.
# ver_of <program>: its version number
ver_of() {
  case "${1##*/}" in
    kubectl) "$1" version --client ;;
    direnv)  "$1" version ;;
    *)       "$1" --version ;;
  esac 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}
# tool_state <command>: installed (with version, and where when it isn't ours) or missing
tool_state() {
  local p; p=$(command -v "$1"); NOTE=""
  [[ -n $p ]] || { STATE=missing; return; }
  STATE=installed; NOTE=$(ver_of "$p")
  [[ $p == "$HOME/.local/bin/$1" ]] || NOTE+=" (${p/#$HOME/\~})"
}
# get_tool <command> "<what it's for>" "<size>" <fetch function>
get_tool() {
  local p; p=$(command -v "$1")
  [[ -n $p ]] && { ok "$1 $(ver_of "$p") is already installed"; return; }
  [[ $OS_KIND == linux && -n $(dl_arch) ]] || { skip "no download for this machine; install $1 yourself"; return; }
  ask "Download the latest $1 into ~/.local/bin? ($2; $3, no sudo)" || { skip; return; }
  "$4" && ok "$1 $(ver_of "$HOME/.local/bin/$1")" || fail "not installed (see the log)"
}
# drop_tool <command>: removes ours from ~/.local/bin; one installed another way stays
drop_tool() {
  if [[ -e "$HOME/.local/bin/$1" ]]; then rm -f "$HOME/.local/bin/$1"; ok "removed $1"
  elif command -v "$1" >/dev/null; then ok "$1 wasn't installed by the toolkit ($(command -v "$1")), so it stays"
  else ok "not installed"; fi
}
# gh_tool <owner/repo> <asset> <command>: newest release asset (a tar.gz holding <command>, or the program itself) into ~/.local/bin
gh_tool() {
  local tmp rc=1
  gh_latest "$1" "$2" || { warn "couldn't find the latest $3 (offline?)"; return 1; }
  tmp=$(mktemp -d)
  if fetch_checked "$GH_URL" "$GH_SHA" "$tmp/dl"; then
    if [[ $2 == *.tar.gz ]]; then tar xzf "$tmp/dl" -C "$tmp" "$3" 2>>"$log_file" && mv "$tmp/$3" "$tmp/dl"; fi &&
      mkdir -p "$HOME/.local/bin" && install -m 755 "$tmp/dl" "$HOME/.local/bin/$3" && rc=0
  fi
  rm -rf "$tmp"
  (( rc )) || logf "$3 $GH_VER installed to ~/.local/bin"
  return "$rc"
}

label_okta_aws_cli() { echo "okta-aws-cli"; }
title_okta_aws_cli() { echo "okta-aws-cli, so okcli can sign you in to AWS through Okta"; }
detail_okta_aws_cli() { echo "latest okta-aws-cli from GitHub (sha256-checked) in ~/.local/bin"; }
state_okta_aws_cli() { tool_state okta-aws-cli; }
install_okta_aws_cli() { get_tool okta-aws-cli "okcli signs in to AWS with it" "about 10 MB" fetch_okta_aws_cli; }
fetch_okta_aws_cli() { gh_tool okta/okta-aws-cli "okta-aws-cli_{v}_linux_$(dl_arch).tar.gz" okta-aws-cli; }
uninstall_okta_aws_cli() { drop_tool okta-aws-cli; }

# AWS's own installer, into ~/.local/aws-cli with aws and aws_completer in ~/.local/bin.
# AWS publishes no checksum for it (only a PGP signature); it comes over HTTPS from AWS.
awscli_dir="$HOME/.local/aws-cli"
label_aws_cli() { echo "AWS CLI v2"; }
title_aws_cli() { echo "The aws command: okcli whoami, kx's EKS sign-in and kx sync need it"; }
detail_aws_cli() { echo "latest AWS CLI v2 from awscli.amazonaws.com in ${awscli_dir/#$HOME/\~}, aws and aws_completer in ~/.local/bin"; }
state_aws_cli() { tool_state aws; }
install_aws_cli() {
  command -v aws >/dev/null || command -v unzip >/dev/null || { skip "unzip is needed to unpack it (sudo apt install unzip)"; return; }
  get_tool aws "okcli and kx's EKS sign-in use it" "about 60 MB" fetch_aws_cli
}
fetch_aws_cli() {
  local arch tmp rc=1
  case "$(dl_arch)" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; esac
  tmp=$(mktemp -d)
  if curl -fsSL --retry 2 -o "$tmp/aws.zip" "https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip" 2>>"$log_file"; then
    unzip -q "$tmp/aws.zip" -d "$tmp" 2>>"$log_file" &&
      "$tmp/aws/install" -i "$awscli_dir" -b "$HOME/.local/bin" --update >>"$log_file" 2>&1 && rc=0
  else warn "couldn't download the AWS CLI (offline?)"; fi
  rm -rf "$tmp"
  return "$rc"
}
uninstall_aws_cli() {
  if [[ -d $awscli_dir ]]; then
    rm -rf "$awscli_dir" "$HOME/.local/bin/aws" "$HOME/.local/bin/aws_completer"; ok "removed the AWS CLI"
  else drop_tool aws; fi
}

label_kubectl() { echo "kubectl"; }
title_kubectl() { echo "kubectl, which kx runs on"; }
detail_kubectl() { echo "latest stable kubectl from dl.k8s.io (sha256-checked) in ~/.local/bin"; }
state_kubectl() { tool_state kubectl; }
install_kubectl() { get_tool kubectl "kx runs on it" "about 60 MB" fetch_kubectl; }
fetch_kubectl() {
  local v url sum tmp rc=1
  v=$(curl -fsS -m 10 https://dl.k8s.io/release/stable.txt 2>>"$log_file") || { warn "couldn't find the latest kubectl (offline?)"; return 1; }
  url="https://dl.k8s.io/release/$v/bin/linux/$(dl_arch)/kubectl"
  sum=$(curl -fsS -m 10 "$url.sha256" 2>>"$log_file") || { warn "couldn't get kubectl's checksum"; return 1; }
  tmp=$(mktemp -d)
  fetch_checked "$url" "$sum" "$tmp/kubectl" && mkdir -p "$HOME/.local/bin" &&
    install -m 755 "$tmp/kubectl" "$HOME/.local/bin/kubectl" && rc=0
  rm -rf "$tmp"
  (( rc )) || logf "kubectl $v installed to ~/.local/bin"
  return "$rc"
}
uninstall_kubectl() { drop_tool kubectl; }

label_direnv() { echo "direnv"; }
title_direnv() { echo "direnv, so okcli pin switches the AWS profile when you cd into a folder"; }
detail_direnv() { echo "latest direnv from GitHub (sha256-checked) in ~/.local/bin; the toolkit's shell setup hooks it in"; }
state_direnv() { tool_state direnv; }
install_direnv() { get_tool direnv "okcli pin needs it" "about 10 MB" fetch_direnv; }
fetch_direnv() { gh_tool direnv/direnv "direnv.linux-$(dl_arch)" direnv; }
uninstall_direnv() { drop_tool direnv; }

# -------------------------------------------------------- eks-clusters ---
# Runs kx sync: tick the AWS accounts to search, then the clusters to add.
# Unticked ones go in ~/.config/kx/ignore, so later syncs skip them.
kx_ignore_file="${XDG_CONFIG_HOME:-$HOME/.config}/kx/ignore"
eks_contexts() { KUBECONFIG="${KX_BASE_KUBECONFIG:-$HOME/.kube/config}" kubectl config get-contexts -o name 2>/dev/null | grep -c .; }
label_eks_clusters() { echo "EKS clusters"; }
title_eks_clusters() { echo "Pick which AWS accounts and EKS clusters kx shows"; }
detail_eks_clusters() { echo "runs kx sync: ticked clusters go in ~/.kube/config, unticked ones in ~/.config/kx/ignore (kx ignore / kx sync to change later)"; }
state_eks_clusters() {
  local n; NOTE=""
  command -v kubectl >/dev/null && command -v aws >/dev/null || { STATE=n/a; NOTE="needs kubectl and the aws CLI"; return; }
  n=$(eks_contexts)
  if (( n )) || [[ -e $kx_ignore_file ]]; then STATE=installed; NOTE="$n context(s) · kx sync / kx ignore to change"
  else STATE=missing; fi
}
install_eks_clusters() {
  (( $(eks_contexts) )) && { ok "already set up ${D}(kx sync / kx ignore to change)${R}"; return; }
  if dry; then say "      ${D}would run kx sync: tick AWS accounts, then the clusters to add${R}"; return; fi
  if ! "$repo/okta/bin/okcli" __profiles 2>/dev/null | grep -q .; then
    warn "okcli has no AWS profiles yet: run ${B}okcli sync${R}, then ${B}kx sync${R}"; return
  fi
  [[ $mode == yes ]] && { skip "pick them yourself: kx sync"; return; }
  ask "Pick your EKS clusters now? (tick accounts, then clusters; unticked ones are skipped from now on)" || { skip "later: kx sync"; return; }
  if "$repo/kube/bin/kx" sync </dev/tty >/dev/tty 2>&1; then ok "done ${D}(kx ignore shows what's skipped)${R}"
  else warn "kx sync didn't finish; run it again with: kx sync"; fi
}
uninstall_eks_clusters() {
  ok "your clusters stay in ~/.kube/config (kx rm <context> removes one); the skip list stays in ${kx_ignore_file/#$HOME/\~}"
}

# --------------------------------------------------------------- repos ---
# Clones what your workspace list names (lines with a GitHub repo) that isn't there
# yet: the layers' shared lists (layers/*/workspaces) plus your own (~/.config/ws/workspaces).
# shellcheck source=workspaces.sh
. "$repo/lib/workspaces.sh"
repos_todo() {   # <path><TAB><owner/repo> for each listed repo not cloned yet
  local p r
  while IFS=$'\t' read -r p r; do
    [[ -n $r && ! -e $p/.git ]] && printf '%s\t%s\n' "$p" "$r"
  done < <(ws_list)
}
# ask_ws_folder NAME "<what goes there>": when the folder a workspace variable
# names ($ACME, ...) doesn't exist yet, show where it would go and let you keep
# that or type another (~/..., /..., or a path inside your home folder), then
# create it and save it in your list. 0 = the folder is there now.
ask_ws_folder() {
  local name=$1 what=$2 cur dir
  cur=$(ws_var "$name")
  [[ -n $cur && -d $cur ]] && return 0
  [[ -n $cur ]] && cur=${cur/#$HOME/\~} || cur="~/$name"
  while :; do
    ask_text "Folder for $what (\$$name)? Enter keeps it; type another to change it" "$cur" || { skip; return 1; }
    dir=$ANSWER
    [[ $dir == "~" || $dir == "~/"* ]] && dir="$HOME${dir:1}"
    [[ $dir == /* ]] || dir="$HOME/$dir"
    dir=$(realpath -m -- "$dir")
    if [[ -z $ANSWER || $ANSWER == *$'\t'* ]]; then warn "that isn't a folder path"
    elif [[ $dir == / || $dir == "$HOME" ]]; then warn "pick a folder of its own, not ${dir/#$HOME/\~}"
    elif [[ -e $dir && ! -d $dir ]]; then warn "${dir/#$HOME/\~} is a file, not a folder"
    elif dry; then say "      ${D}would create ${dir/#$HOME/\~} and save $name there in your list${R}"; return 0
    elif ! mkdir -p -- "$dir" 2>/dev/null; then warn "can't create ${dir/#$HOME/\~} (no permission?)"
    else
      ws_set_var "$name" "$dir"
      ok "$name → ${dir/#$HOME/\~} ${D}(saved in $(ws_list_file | sed "s|^$HOME|~|"); ws edit changes it)${R}"
      return 0
    fi
    [[ $mode == yes ]] && return 1   # --yes can't ask again
    cur=$ANSWER
  done
}

label_repos() { echo "Workspace repos"; }
title_repos() { echo "Clone the repos in your workspace list (ws edit) that aren't there yet"; }
detail_repos() { echo "git clone over SSH into the folders your workspace list names; creates ~/.config/ws/workspaces"; }
state_repos() {
  local all todo
  all=$(ws_list | awk -F'\t' '$2 != ""' | wc -l)
  todo=$(repos_todo | grep -c . )
  NOTE=""
  if (( todo == 0 )); then STATE=installed
  elif (( todo < all )); then STATE=partial; NOTE="$((all - todo)) of $all cloned"
  else STATE=missing; fi
}
install_repos() {
  local out p r labels=() todo=() on="" i
  # Your own list, outside the repo (team repos included); edit it with: ws edit
  if [[ ! -e "$(ws_list_file)" ]] && ! dry; then
    ws_personal_init >/dev/null && ok "your workspace list: $(ws_list_file | sed "s|^$HOME|~|") ${D}(ws edit)${R}"
  fi
  # where each group of repos goes ($ACME, ...), asked once while its folder isn't there
  local v vd
  while IFS= read -r v; do
    vd=$(ws_var "$v")
    [[ -n $vd && ! -d $vd ]] && repos_todo | grep -q "^$vd/" && ask_ws_folder "$v" "the repos under \$$v"
  done < <(ws_vars)
  mapfile -t todo < <(repos_todo)
  (( ${#todo[@]} )) || { ok "all cloned"; return; }
  # Check GitHub SSH first: one clear message instead of a failure per repo.
  out=$(ssh -T -o BatchMode=yes -o ConnectTimeout=8 git@github.com 2>&1)
  if [[ $out != *"successfully authenticated"* ]]; then
    fail "GitHub SSH auth isn't working, so skipping repos: $(head -1 <<<"$out")"
    say "      ${D}Check: ssh -T git@github.com · then: ./install.sh repos${R}"
    return
  fi
  ok "GitHub SSH works ($(grep -o 'Hi [^!]*' <<<"$out"))"
  if dry; then
    for i in "${todo[@]}"; do say "      ${D}would clone ${i#*$'\t'} → ${i%%$'\t'*}${R}" | sed "s|$HOME|~|"; done
    return
  fi
  if [[ $mode == ask ]]; then
    for i in "${!todo[@]}"; do
      labels+=("$(basename "${todo[i]%%$'\t'*}")"$'\t'"${todo[i]#*$'\t'}"); on+="$i "
    done
    CHECKLIST_ON=$on checklist "      Missing repos (all ticked; space unticks):" "${labels[@]}" || { skip; return; }
    local picked=(); for i in "${CHECKLIST[@]}"; do picked+=("${todo[i]}"); done
    todo=("${picked[@]}")
    (( ${#todo[@]} )) || { skip "nothing picked"; return; }
  fi
  for i in "${todo[@]}"; do
    p=${i%%$'\t'*}; r=${i#*$'\t'}
    if [[ -e $p ]]; then warn "$(basename "$p"): folder exists but isn't a git repo, left alone"; continue; fi
    mkdir -p "$(dirname "$p")"
    if git clone -q "git@github.com:$r.git" "$p" >>"$log_file" 2>&1; then ok "$(basename "$p")"
    else warn "$(basename "$p"): couldn't clone $r (no access, or it doesn't exist); skipped"; fi
  done
}
# clone_unpushed <dir>: 0 when the clone holds work that isn't on GitHub yet
# (uncommitted, no upstream, or commits not pushed), so it must never be deleted.
clone_unpushed() {
  [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]] && return 0
  git -C "$1" rev-parse '@{u}' >/dev/null 2>&1 || return 0
  [[ -n $(git -C "$1" log --oneline '@{u}..' 2>/dev/null) ]]
}
uninstall_repos() {
  local p r safe=() kept=() names d n
  while IFS=$'\t' read -r p r; do
    [[ -n $r && -d $p/.git && $p == "$HOME"/?* ]] || continue
    if clone_unpushed "$p"; then kept+=("$p"); else safe+=("$p"); fi
  done < <(ws_list)
  (( ${#safe[@]} + ${#kept[@]} )) || { ok "no cloned workspace repos found"; return 0; }
  for d in "${kept[@]}"; do warn "${d/#$HOME/\~} has work that isn't on GitHub yet (uncommitted or not pushed), so it stays"; done
  (( ${#safe[@]} )) || return 0
  if [[ $mode == yes ]]; then ok "the ${#safe[@]} clones stay (--yes never deletes folders)"; return 0; fi
  n=${#safe[@]}; names=$(printf '%s, ' "${safe[@]:0:4}" | sed "s|$HOME|~|g; s|, \$||")
  (( n > 4 )) && names+=", and $(( n - 4 )) more"
  if ask "Also delete $n workspace clone(s) with nothing unpushed? ($names)" n; then
    dry || { for d in "${safe[@]}"; do rm -rf -- "$d"; done; ok "$n clone(s) deleted"; }
  else ok "the clones stay"; fi
}

# -------------------------------------------------------------- claude ---
# Claude Code reads its config from $CLAUDE_CONFIG_DIR (shell/common.sh sets it),
# else ~/.claude. The skill teaches Claude the toolkit; the hook hands it
# `ctx plain` at the start of every session.
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cs_pairs() {   # <link><TAB><skill folder>: the toolkit's skill, then each layer's
  local d
  for d in "$repo"/claude/skills/*/ "$repo"/layers/*/claude/skills/*/; do
    [[ -d $d ]] && printf '%s\t%s\n' "$claude_dir/skills/$(basename "$d")" "${d%/}"
  done
}
label_claude_skill() { echo "Claude skill"; }
title_claude_skill() { echo "Claude Code knows okcli, kx, ctx and the rest, in every repo"; }
detail_claude_skill() { echo "${claude_dir/#$HOME/\~}/skills/<name> links to claude/skills/<name> (and each layer's)"; }
state_claude_skill() { local l t n=0 all=0; NOTE=""
  command -v claude >/dev/null || [[ -d "$claude_dir" ]] || { STATE=n/a; NOTE="Claude Code isn't installed"; return; }
  while IFS=$'\t' read -r l t; do (( all++ )); linked "$l" "$t" && (( n++ )); done < <(cs_pairs)
  if (( n == all )); then STATE=installed; elif (( n )); then STATE=partial; NOTE="$n of $all skills linked"; else STATE=missing; fi; }
install_claude_skill() { local l t
  while IFS=$'\t' read -r l t; do
    linked "$l" "$t" && { ok "$(basename "$l"): already linked"; continue; }
    [[ -e "$l" && ! -L "$l" ]] && { warn "${l/#$HOME/\~} exists and isn't a link; left alone"; continue; }
    ask "Teach Claude Code the $(basename "$l") skill? (in ${claude_dir/#$HOME/\~}/skills)" && { dry || link_file "$l" "$t"; } || skip
  done < <(cs_pairs); }
uninstall_claude_skill() { local l t; while IFS=$'\t' read -r l t; do unlink_file "$l" "$t"; done < <(cs_pairs); }

# The hook is the one SessionStart entry whose command is $ch_cmd. settings.json
# is edited as JSON (python), everything else in it is kept as is.
ch_settings="$claude_dir/settings.json"
ch_cmd="ctx plain 2>/dev/null || true"
ch_json() {   # ch_json has|add|remove  (add/remove print the new settings)
  python3 -I - "$ch_settings" "$ch_cmd" "$1" <<'PY'
import json, os, sys
path, cmd, op = sys.argv[1:]
d = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
ss = d.setdefault("hooks", {}).setdefault("SessionStart", [])
mine = lambda g: any(h.get("command") == cmd for h in g.get("hooks", []))
if op == "has":
    sys.exit(0 if any(mine(g) for g in ss) else 1)
ss[:] = [g for g in ss if not mine(g)]
if op == "add":
    ss.append({"hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
if not ss: del d["hooks"]["SessionStart"]
if not d["hooks"]: del d["hooks"]
print(json.dumps(d, indent=2))
PY
}
ch_write() {   # ch_write add|remove
  local tmp b; tmp=$(mktemp)
  ch_json "$1" >"$tmp" || { rm -f "$tmp"; fail "couldn't read ${ch_settings/#$HOME/\~} (not valid JSON?)"; return 1; }
  mkdir -p "$claude_dir"; b=$(backup "$ch_settings")
  cat "$tmp" >"$ch_settings"; rm -f "$tmp"
  logf "  $1 SessionStart hook in $ch_settings${b:+ (backup: $b)}"
  ok "done${b:+ (backup: ${b/#$HOME/\~})}"
}
label_claude_hook() { echo "Claude start hook"; }
title_claude_hook() { echo "Every Claude Code session starts knowing your AWS profile, pin and cluster"; }
detail_claude_hook() { echo "a SessionStart hook in ${ch_settings/#$HOME/\~} that runs: $ch_cmd"; }
state_claude_hook() { NOTE=""
  command -v claude >/dev/null || [[ -d "$claude_dir" ]] || { STATE=n/a; NOTE="Claude Code isn't installed"; return; }
  if ch_json has 2>/dev/null; then STATE=installed; else STATE=missing; fi; }
install_claude_hook() { ch_json has 2>/dev/null && { ok "already there"; return; }
  ask "Add the start hook to ${ch_settings/#$HOME/\~}? (runs ${C}ctx plain${R} when a session opens)" && { dry || ch_write add; } || skip; }
uninstall_claude_hook() { ch_json has 2>/dev/null || { ok "not there"; return 0; }; ch_write remove; }

# The coding guidelines (claude/guidelines/karpathy.md, a vendored copy; refresh
# it with `tk guidelines refresh`) live in the user-level CLAUDE.md as one block
# between markers, so everything outside the markers stays yours.
cg_src="$repo/claude/guidelines/karpathy.md"
cg_file="$claude_dir/CLAUDE.md"
cg_json() {   # cg_json has|add|remove  (has: block there and current; add/remove print the new file)
  python3 -I - "$cg_file" "$cg_src" "$1" <<'PY'
import os, re, sys
path, src, op = sys.argv[1:]
S, E = "<!-- tk:karpathy-guidelines:start -->", "<!-- tk:karpathy-guidelines:end -->"
lines = open(src).read().splitlines()
lines[0] = "# Coding guidelines (andrej-karpathy-skills)"
block = S + "\n" + "\n".join(lines).rstrip() + "\n" + E
text = open(path).read() if os.path.exists(path) else ""
pat = re.compile(re.escape(S) + r".*?" + re.escape(E), re.S)
if op == "has":
    m = pat.search(text)
    sys.exit(0 if m and m.group(0) == block else 1)
rest = pat.sub("", text).strip("\n")
if op == "add":
    # keep the block where it was; otherwise append it
    out = pat.sub(lambda _: block, text, count=1) if pat.search(text) else (rest + "\n\n" if rest else "") + block + "\n"
else:
    out = rest + "\n" if rest else ""
sys.stdout.write(out)
PY
}
cg_write() {   # cg_write add|remove
  local tmp b; tmp=$(mktemp)
  cg_json "$1" >"$tmp" || { rm -f "$tmp"; fail "couldn't update ${cg_file/#$HOME/\~}"; return 1; }
  mkdir -p "$claude_dir"; b=$(backup "$cg_file")
  if [[ -s "$tmp" ]]; then cat "$tmp" >"$cg_file"; else rm -f "$cg_file"; fi
  rm -f "$tmp"
  logf "  $1 coding guidelines in $cg_file${b:+ (backup: $b)}"
  ok "done${b:+ (backup: ${b/#$HOME/\~})}"
}
cg_present() { [[ -f "$cg_file" ]] && grep -q 'tk:karpathy-guidelines:start' "$cg_file"; }
label_claude_guidelines() { echo "Claude guidelines"; }
title_claude_guidelines() { echo "Claude Code follows the same coding guidelines in every project (think first, keep it simple, small diffs)"; }
detail_claude_guidelines() { echo "one marked block in ${cg_file/#$HOME/\~}; the rest of that file is left alone"; }
state_claude_guidelines() { NOTE=""
  command -v claude >/dev/null || [[ -d "$claude_dir" ]] || { STATE=n/a; NOTE="Claude Code isn't installed"; return; }
  if cg_json has 2>/dev/null; then STATE=installed
  elif cg_present; then STATE=partial; NOTE="out of date"
  else STATE=missing; fi; }
install_claude_guidelines() { cg_json has 2>/dev/null && { ok "already there"; return; }
  ask "$(cg_present && echo Update || echo Add) the coding guidelines in ${cg_file/#$HOME/\~}? (every Claude Code project)" && { dry || cg_write add; } || skip; }
uninstall_claude_guidelines() { cg_present || { ok "not there"; return 0; }; cg_write remove; }

# -------------------------------------------------------------- layers ---
# Each layer's own components (lib/layers.sh), after the toolkit's.
# shellcheck source=layers.sh
. "$repo/lib/layers.sh"
# layer_parts <name>: the components that layer adds, plus claude-skill when it brings skills
declare -gA LAYER_OF=()
while IFS= read -r _layer; do
  _n=${#COMPONENTS[@]}
  # shellcheck disable=SC1090
  [[ -r $_layer/components.sh ]] && . "$_layer/components.sh"
  for _id in "${COMPONENTS[@]:_n}"; do LAYER_OF[$_id]=${_layer##*/}; done
done < <(layer_dirs "$repo")
unset _layer _n _id
# A layer's components land at the end of COMPONENTS; bring each group together again, groups
# in the order they first appear and components in their order inside a group.
_regroup() {
  local id g; local -a order=() out=()
  for id in "${COMPONENTS[@]}"; do g=$(group_of "$id"); [[ " ${order[*]} " == *" ${g// /_} "* ]] || order+=("${g// /_}"); done
  for g in "${order[@]}"; do
    for id in "${COMPONENTS[@]}"; do [[ $(group_of "$id") == "${g//_/ }" ]] && out+=("$id"); done
  done
  COMPONENTS=("${out[@]}")
}
_regroup; unset -f _regroup
layer_parts() {
  local id
  for id in "${COMPONENTS[@]}"; do [[ ${LAYER_OF[$id]:-} == "$1" ]] && echo "$id"; done
  local d; d=$(layer_path "$repo" "$1") && compgen -G "$d/claude/skills/*/" >/dev/null && echo claude-skill
  return 0
}
