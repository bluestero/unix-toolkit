# unix-toolkit

A shell toolkit for work: AWS profiles, Kubernetes, Twingate, workspaces, a themed kitty, all behind one front door (`tk`). Your company's own parts (repos, settings, extra commands) come as a [layer](#layers) from their own repo.

Every command speaks the same words: `<tool>` picker, `<tool> <name>` switch, `ls`, `status`, `current`, `default [name]`, `off`, `doctor`, `help` (see the top of `lib/ui.sh`). Anything else is an error.

| Tool | What it does |
|---|---|
| `tk` | The front door: `tk` picks and runs any toolkit command, `tk ls` lists them, `tk status` (ctx + how much is set up), `tk doctor` (every check in one box), `tk install` / `tk uninstall` from anywhere, `tk update` pulls the latest (layers too) and shows what changed, `tk layer` adds or removes [layers](#layers), `tk version` shows the version. |
| `okcli` | Okta AWS profiles: picker, refresh-all, per-shell switch, global default, repo pins. See `okta/README.md`. |
| `kx` | Kubernetes contexts **per shell** (switching in one terminal never moves another), namespaces, global default, EKS contexts linked to okcli profiles. Also a friendly front to kubectl: `kx pods`, `why`, `logs`, `shell`, `deploys`, `configs`, `secrets`, `services`, `forward`, `events`, `top`, `get` (see `kx help`). |
| `twin` | Twingate exit nodes: picker, `twin gb`, `twin off`. Codes come from the node names. |
| `ws` | Open workspaces in your IDE. Picker: ↑↓ pick, ←→ switch IDE (● = already open there, gets focused), tab ticks several, ctrl-x closes the window (needs `window-calls`). `ws <name>`, `ws close <name>`, `ws ls`, `ws default [ide]`, `ws edit` (your list: `~/.config/ws/workspaces`, which can include your layers' shared lists). |
| `hat` | Which Claude profile, GitHub account and AWS profile a folder uses, for every repo under it. `hat` is a panel of folders (enter change, alt-a add a folder, ctrl-x take off, alt-c Claude profiles, alt-g GitHub accounts); `hat set ~/code claude=personal github=me`, `hat ls`, `hat show`, `hat github add <account>` (makes the SSH key too). `ws ls` shows each workspace's. See [Hats](#hats-claude-github-and-aws-per-folder). |
| `ctx` | One screen: AWS profile, cluster/namespace, Twingate, defaults and repo pin. `ctx plain` gives the same as labelled lines (what Claude Code gets). |
| `k-icon` | Kitty app icon: picker, `k-icon <name>`, `k-icon ls`. |
| `k-config` | Edit `kitty/kitty.conf` (the file kitty reads through the link) in `$EDITOR` (else nano); warns if the link is missing. kitty reloads it by itself on save (0.47+). |
| `k-bg` | Kitty background picker: the image previews live as you move through the list; ←/→ image brightness, shift+←/→ opacity (live); Enter keeps it, Esc puts the old one back. `k-bg <name>` / `k-bg off` / `k-bg bright 40` / `k-bg opacity 85` / `k-bg ls` / `k-bg status` / `k-bg accents on\|off`. Images live in `kitty/backgrounds/`. |
| `k-theme` | Kitty colour theme picker with two tabs, ←/→ to switch: **Mine** (your short list, `~/.config/k-theme/mine`, everyone has their own; it always opens here) and **All** (every other theme: yours plus kitty's 400+). Colours preview live as you move; type to search. `ctrl-a` in All moves a theme to Mine, `ctrl-d` in Mine moves it back (Tab ticks several first). `ctrl-f` shows all → only dark → only light, in both tabs (your own themes are sorted by their background colour). Enter keeps the theme, Esc puts the old one back. Import a downloaded theme: drop the `.conf` in `~/.config/kitty/themes/` (or the team's `kitty/themes/`), or `k-theme add <file or URL> [name]`. `k-theme add <name>` / `rm <name>` / `<name>` / `default` / `ls [all]` / `status` / `update`. Only colour lines are taken from a theme, and k-bg accents still win for the cursor, selection and tabs. The tabs need fzf 0.60+ (`./install.sh fzf`); older fzf gets one list. |
| starship | `starship/starship.toml`: git, python, k8s context/namespace, AWS profile and expiry, loud **PROD** markers. |

## Set it up on your machine (teammates)

For Ubuntu with GNOME. About 10 minutes; nothing changes without asking first. On other systems (Arch, KDE, macOS) the installer checks each part against the machine and marks what can't run there `⊘ not supported here`, with the reason (needs GNOME, needs apt, Linux only for now); those are left out of the checklist.

**1. Install what the tools run on.** The installer sets up the toolkit itself, kitty and zsh,
but not these. Install the ones for the tools you'll use:

| You want | Install |
|---|---|
| everything | `sudo apt install git curl fzf direnv` |
| `okcli` (AWS) | [okta-aws-cli](https://github.com/okta/okta-aws-cli) v2 and the [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| `kx` (Kubernetes) | [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) (plus the AWS CLI for EKS) |
| `twin` | the [Twingate client](https://www.twingate.com/download) |
| the prompt | [starship](https://starship.rs) |

**2. Install.** One command: it clones the toolkit into `~/.local/share/unix-toolkit` (or updates
it if it's there) and starts the installer. Everything is ticked, so Enter sets it all up; untick
what you don't want. Each change still asks first (Enter = yes).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bluestero/unix-toolkit/main/bootstrap.sh)
```

Your company has a layer? Add `--layer <its git URL>` (repeat for several) and its parts are in
the same checklist. `--dir <folder>` puts the toolkit elsewhere. Or clone it yourself, anywhere,
and run `./install.sh`: the installer records where it is.

**3. Open a new terminal and check.** `tk doctor` lists anything left, each with the command that fixes it.

```bash
tk doctor
```

**4. First run of each tool:**

| Command | Does |
|---|---|
| `okcli sync` | sign in to Okta once, tick the AWS account and role pairs to keep (your Okta org comes from your layer, or `export OKTA_AWSCLI_ORG_DOMAIN=… OKTA_AWSCLI_OIDC_CLIENT_ID=…`) |
| `okcli default <profile>` | what new terminals start on (pick a dev one) |
| `kx sync` | find the EKS clusters your AWS roles can see, tick which to keep (unticked ones are skipped from then on) |
| `kx ignore` | what `kx sync` skips; `kx ignore <context\|cluster\|account>` hides one, `kx unignore <name>` brings it back |
| `kx default <context>` | the cluster new terminals start on |
| `ws edit` | your workspace list: add your own folders and repos (see below) |
| `ctx` | check what this terminal points at |
| `tk` | everything else: a picker of every command |

**Your workspace list** is `~/.config/ws/workspaces`, outside the repo, so it's yours to edit
(`ws edit`) and updates never change it. `ws` opens what's in it, and `tk install repos` clones
any listed repo you don't have yet. A line `NAME=folder` sets a folder the paths below can use
as `$NAME`, and `@<layer>` brings in a layer's shared list:

```
ACME=~/work/acme                  # where the "acme" layer's repos go; change it to keep them elsewhere
@acme                             # that layer's shared list (layers/acme/workspaces); delete to leave it out
~/code/my-project   me/my-project # your own: a folder, then optionally its GitHub repo to clone
```

A new list starts with one such pair per layer you have. New team repos go in the layer's
`workspaces` file, so everyone gets them on `tk update`.

**Updates:** `tk update` pulls the latest toolkit and every layer, shows the version change and what's new, and sets up anything new. Maintainers: bump `VERSION` (1.2.0 → 1.3.0 for new things, → 1.2.1 for fixes) when you push something the team will notice.

**Removing it:** `tk uninstall` shows a checklist of what's installed, and puts back what you had
before (see [Going back to your own setup](#going-back-to-your-own-setup)).

## Layers

A layer is a folder in `layers/<name>/`, from its own repo, that adds to the toolkit without
changing it: a company's settings, team repos and commands stay in a private repo, and the
toolkit stays general. `layers/` is gitignored; there's nothing to register.

```bash
tk layer add git@github.com:acme/acme-toolkit.git   # clones into layers/acme (-toolkit dropped), offers to set it up
tk layer ls                                          # what's there, where from, which version
tk layer rm acme                                     # deletes it (refuses while it has unpushed work)
```

Copying a folder into `layers/` works too (no updates then). Everything in a layer is optional:

| In the layer | What the toolkit does with it |
|---|---|
| `bin/` | on PATH in every shell |
| `shell/init.sh` | sourced by bash and zsh before the tools load: settings they read (`OKTA_AWSCLI_ORG_DOMAIN`, `OKTA_AWSCLI_OIDC_CLIENT_ID`, `OKCLI_NAMING_DEFAULT`, `KX_ALIAS_RULES`), aliases |
| `components.sh` | installer components (`COMPONENTS+=(…)` and the usual functions; `group_<id>` names the checklist group) |
| `tools` | commands for `tk ls` and the `tk` picker: `name\|group\|what it does\|program it needs` |
| `workspaces` | a shared `ws` list; `@<name>` in your own list brings it in |
| `claude/skills/<skill>/` | Claude Code skills, linked by the `claude-skill` component |
| `claude/guidelines/` | Vendored coding guidelines, merged into `CLAUDE.md` by the `claude-guidelines` component |

`lib/layers.sh` has the same list for whoever writes one.

## Install / uninstall

```bash
./install.sh ls          # what's installed
./install.sh             # checklist of what's missing, then one question per change (Enter = yes)
./install.sh zsh         # just one part
./install.sh --dry-run   # preview; --details also shows diffs
./uninstall.sh           # checklist of what's installed; pick what to remove
./install.sh --plain     # never use or offer gum
```

The checklist splits into **Recommended** (bash, keys, commands, starship) and **Optional**
(kitty and zsh extras), all ticked: Enter sets everything up, and each change still asks first.
If [gum](https://github.com/charmbracelet/gum) isn't installed, the installer offers to fetch it
(v2.0.2, checksum-checked, into `~/.local/bin`, no sudo) for nicer lists and questions; say no
and the plain built-in ones are used. Remove it with `rm ~/.local/bin/gum`.

Both are safe to run any number of times: they check first and only touch what's missing
(or still there). Replaced files are backed up as `<file>.bak-<time>`, and uninstall puts
the backup back. Log: `~/.local/state/work-toolkit/setup.log`.

### Going back to your own setup

The toolkit never overrides your own aliases: `shell/common.sh` only adds an alias you don't
have yet (yours from `~/.bashrc` or `~/.zshrc` wins), and your own `dex` function wins too.
The first time the installer changes something of yours, it keeps what you had in
`~/.local/state/work-toolkit/originals/` (once, never overwritten). Uninstalling puts back:

| What | Put back on uninstall |
|---|---|
| `~/.bashrc` | the lines the installer took out go back where they were; whatever you edited since stays |
| `~/.inputrc`, `starship.toml`, `kitty.conf` | your own file (they were links to the repo) |
| `~/.zshrc`, `~/.zprofile`, `~/.zshenv` | only the toolkit's marked block is removed |
| default terminal, Ctrl+Alt+T | what you had set before (else the system default) |
| login shell | the one you had before (else bash) |
| Claude Code `settings.json` | only the toolkit's hook entry is removed |

| Component | What it sets up |
|---|---|
| `bash` | `~/.bashrc` keeps the Ubuntu defaults plus one line loading `shell/init.sh`; PATH, nvm, direnv/starship hooks and exact copies of the toolkit's aliases move into the repo, clashing leftovers (ble.sh, old okcli hooks, duplicate nvm) are removed. Your own aliases stay. Uninstall puts the removed lines back |
| `btop` | installs btop (apt) if missing, links `~/.config/btop/btop.conf` → `btop/btop.conf`, and has k-theme write btop's colours from your kitty theme (re-done on every theme change). Uninstall puts your own btop config back |
| `yazi` | yazi 26.9.1 (terminal file manager) from GitHub in `~/.local/bin`, checked against a pinned sha256; also `ya`. The `y` command (`yazi/shell/y.sh`, loaded by `shell/init.sh`) opens it and leaves your shell in the folder you quit in (`q`; `Q` quits without cd). Colours follow the kitty theme through the terminal palette. Uninstall removes the binaries; `~/.config/yazi` stays |
| `keys` | `~/.inputrc` → `shell/inputrc` (case-insensitive Tab, Up/Down search by what's typed) |
| `commands` | `okcli`, `kx`, `twin`, `ctx`, `ws` in `~/.local/bin` |
| `starship` | `~/.config/starship.toml` → `starship/starship.toml` |
| `fzf` | fzf 0.74.5 from GitHub (checksum-checked) in `~/.local/bin`, ahead of Ubuntu's 0.44. Every picker then shows where you are (`12/426`, `3/17 of 426` while searching), and k-theme gets its tabs. Uninstall goes back to apt's |
| `kitty` | the kitty terminal itself: the latest official build (checksum-checked) in `~/.local/kitty.app`; `kitty`/`kitten` in `~/.local/bin`, the app menu entry and Ctrl+Alt+T point at it. Ubuntu's apt kitty stays as the fallback (uninstall goes back to it). `./install.sh ls` shows when there's a newer one |
| `kitty-config` | `~/.config/kitty/kitty.conf` → `kitty/kitty.conf` |
| `kitty-bg` | apt `imagemagick` (and fzf if there's none) for the `k-bg` picker, then a first pick (live preview; Esc = no background). Uninstall: background off, resized copies removed |
| `kitty-theme` | kitty's theme collection (about 0.6 MB from GitHub), a current fzf if yours is older than 0.60, then an optional first pick with `k-theme`. Uninstall: back to kitty's colours (your Mine list stays) |
| `kitty-accents` | `k-bg accents on`: a vivid colour from the background (always readable against it, never red) for the prompt's directory, `❯` and git branch, the toolkit's pickers and highlights, and kitty's cursor, selection, links, active tab and border. Terminal colours and red prod warnings stay put |
| `zsh` | apt `zsh zsh-autosuggestions`; `~/.zshrc`, `~/.zprofile`, `~/.zshenv` each get one managed block |
| `login-shell` | `chsh` to zsh (log out once) |
| `kitty-icons` | `kitty/install-kitty-icons.sh` (icons + desktop entry for `k-icon`) |
| `kitty-nautilus` | `kitty/install-kitty-gnome.sh` (kitty as default terminal, Open in Terminal in Files; Ctrl+Alt+T focuses the open kitty window, or starts kitty, via `kitty/bin/kitty-focus`, and Ctrl+Shift+Alt+T opens a new window) |
| `kitty-centered` | GNOME setting `org.gnome.mutter center-new-windows`, so new windows (kitty included) open in the middle of the screen; the old value is put back on uninstall |
| `window-calls` | GNOME extension Window Calls (from extensions.gnome.org) so `ws` can close and focus editor windows; log out once after installing |
| `alt-tab-desktop` | GNOME extension in `gnome/`: after Super+D (show desktop), Alt+Tab returns to the window you minimized instead of the one before it; log out once after installing |
| `dash-to-panel` | Dash to Panel (GNOME extension) from extensions.gnome.org: the dock and the top bar merged into one bar (app icons with window previews on the left; clock, Vitals and system menu on the right; no Activities button). Preset look from `gnome/dash-to-panel/` (bottom, 35 px, dark, own apps-button icon). Your choice: on its own or together with `dash2dock`; asked separately, default No; the uninstall puts your old settings back; log out once after installing |
| `dash2dock` | Dash2Dock Animated (macOS-style GNOME dock at the bottom) from extensions.gnome.org, with the toolkit's patches in `gnome/dash2dock/`: a click on an app with several windows shows window previews, calm drag-to-reorder, no gap above the dock; plus a preset look. Replaces Ubuntu's dock; your choice, alone or together with Dash to Panel; asked separately, default No; the uninstall puts that back; log out once after installing |
| `hide-docker-tray` | Small GNOME extension (`gnome/hide-docker-tray@work-toolkit`, linked in) that hides Docker Desktop's tray item: no icon, empty menu, three dots that do nothing on click; log out once after installing |
| `app-keys` | Super+1..9 for the Nth pinned dock app: launches it, brings it to the front, or minimizes it when it is already in front (`bin/k-appkey`, one short process per key press, no background process; uses Window Calls). Turns GNOME's own Super+number off; the uninstall puts it back; asked with default No |
| `vitals-icons` | Two SVGs in `gnome/vitals-icons` (CPU chip with a solid core, RAM chip with pins) copied over the Vitals extension's `icons/original` icons, and its dropdown is centred under the pill (`menu-centered`, old value put back on uninstall); stock ones kept as `*.toolkit-orig` for the uninstall. An extension update restores the stock icons, so run it again after one |
| `rofi` | apt `rofi`; `~/.config/rofi/config.rasi` → `rofi/config.rasi` (minimal; `colors.rasi` is written by `kitty/bin/k-rofi` from the kitty colours in use, and `k-theme` / `k-bg` re-run it on every change); GNOME shortcuts Alt+Space (open windows first, then apps; pick a window to focus it), Alt+Shift+Space (ssh), Super+S (speaker, mic, wifi, bluetooth: pick a row to switch; Ctrl+Tab / Ctrl+Shift+Tab cycle the four; a new secured wifi network asks for its password in the list) and Super+X (power: lock, suspend, hibernate, log out, restart, shut down; the last three ask first). Inside: Tab / Ctrl+Tab switches between apps, ssh, files and power; Esc closes. The shortcuts use `-normal-window` so it gets the keyboard on Wayland |
| `no-animations` | GNOME setting `org.gnome.desktop.interface enable-animations = false`: no window zoom animations (snappier, and no blurry flash when the rofi launcher opens and closes fast); asked with default No, old value put back on uninstall |
| `eks-clusters` | Runs `kx sync` (after `okcli sync`): tick the AWS accounts, then the EKS clusters you want. Unticked ones go in `~/.config/kx/ignore`. Skipped if you already have contexts. |
| `repos` | Checks `ssh -T git@github.com`, then clones the repos in your workspace list that are missing: your layers' shared lists plus your own (checklist, all ticked). Creates your list (`~/.config/ws/workspaces`) if needed. Never deletes clones. |
| `claude-skill` | Links `claude/skills/work-toolkit` (and each layer's skills) into Claude Code's skills (`$CLAUDE_CONFIG_DIR`, else `~/.claude`), so Claude knows okcli, kx, ctx and the rest in every repo: run AWS and kubectl through `okcli exec` / `kx exec` / `direnv exec`, and ask before prod changes or defaults |
| `claude-hook` | Adds a SessionStart hook to Claude Code's `settings.json` that runs `ctx plain`, so every session starts knowing the AWS profile (and if it's PROD), the repo pin and the cluster. Only that one entry is added or removed; the rest of the file is kept |
| `claude-guidelines` | Adds the coding guidelines (`claude/guidelines/karpathy.md`, a vendored copy of andrej-karpathy-skills' `CLAUDE.md`) to Claude Code's user-level `CLAUDE.md` (`$CLAUDE_CONFIG_DIR`, else `~/.claude`), so they apply in every project. Only the block between the `tk:karpathy-guidelines` markers is added, updated or removed; the rest of the file is kept. `tk guidelines refresh` fetches upstream and shows the diff before replacing the copy |

## zsh

`zsh/zshrc` is small: shared history, the bash keys, an arrow-key Tab menu (case-insensitive),
and faded grey suggestions from history (Shift+Tab, → or End accepts, Alt+F one word; Tab is normal completion). Then it loads
`shell/init.sh`, so zsh gets exactly the same aliases and tools as bash. Your own zsh tweaks go
in `~/.zshrc` outside the managed block.

## Hats: Claude, GitHub and AWS per folder

Not an installer step: set it up when you need it, with `hat`.

| | Where it goes | Covers |
|---|---|---|
| Claude profile | `export CLAUDE_CONFIG_DIR=…` in the folder's `.envrc` (direnv); profiles are `~/.claude-profiles/<name>` | everything under the folder |
| AWS profile | `export AWS_PROFILE=…` in the `.envrc`, the same line `okcli pin` writes | everything under the folder |
| GitHub account | `[includeIf "gitdir:<folder>/"]` in `~/.gitconfig` → `~/.config/hat/github/<account>.gitconfig` | every repo under the folder |

A GitHub account is its commit name and email plus its SSH key; its own small ssh config
offers that key first, so plain `git@github.com:` remotes sign in as that account. `.envrc`
files hat writes start with `source_up_if_exists`, so a repo's own `.envrc` doesn't drop its
parent folder's hat. A hat on a folder inside another one wins there.

`hat` lists every folder wearing a hat, however it got it (hat, `okcli pin`, or an `.envrc`
you wrote). In `hat ls` and `ws ls`: `↑` from a parent folder, `⇄` set in the repo itself
(its own git config), `–` the default.

## Pin, switch, default (AWS and Kubernetes work the same way)

| Level | AWS | Kubernetes | Scope |
|---|---|---|---|
| pin | `okcli pin shop-dev` | — | this repo (direnv `.envrc`) |
| switch | `okcli shop-dev-ro` | `kx shop-dev`, `kx ns kube-system` | this shell only |
| default | `okcli default shop-dev` | `kx default shop-dev` | new terminals |

Making a prod profile/cluster the default asks for confirmation. Pickers open on a non-prod entry.

## First run with kx

```bash
okcli sync              # every account+role you have, named <account>-<role>; tick and save
kx sync                 # tick accounts -> finds their EKS clusters -> tick which to keep
                        # (unticked accounts/clusters go in ~/.config/kx/ignore and are skipped next time)
kx tidy                 # short names, link each cluster to its eks-<cluster>-read/admin role
kx default shop-dev     # global default off prod
kx doctor
```

Changing your mind later: run `kx sync` again (untick an added cluster to remove it, tick an
ignored one to add it back), or `kx ignore shop-poc` / `kx ignore <account>` / `kx unignore <name>`,
`ctrl-x` in the `kx` picker, `kx rm <context>` (remove, but let sync offer it again), or edit the
list with `kx ignore edit`.

Linked contexts authenticate with their own AWS profile (`AWS_PROFILE` in the kubeconfig
exec credentials), so `kubectl` on `shop-prod` uses `prod-ro` even while your shell is on
`shop-dev`. Change a link with `kx link <ctx> <profile>`.

## Layout

```
bin/ctx, bin/tk             overview (ctx) and the toolkit's front door (tk)
lib/ui.sh                   shared look + command rules for every command (box, help, colours, fzf)
lib/setup.sh, components.sh install/uninstall plumbing and the component list
lib/platform.sh             OS, distro, package manager, GNOME? (components.sh `requires_of` says what each part needs)
lib/bashrc_plan.py          the ~/.bashrc cleanup (same result every run)
lib/bashrc_restore.py       uninstall: puts the lines the cleanup took out back
okta/                       okcli and its README
kube/bin/kx, kube/shell/    kx and its shell hook
twingate/bin/twin, shell/   twin
ws/bin/ws, shell/           ws (lib/workspaces.sh reads the lists)
bin/hat, lib/hat.sh         hat: Claude, GitHub and AWS per folder
lib/layers.sh               what a layer can hold; layers/ (gitignored) holds them
claude/skills/work-toolkit/ the Claude Code skill (what each tool is for, what to ask before)
kitty/                      kitty config, installers, k-icon, k-bg, k-theme (kitty/bin) + backgrounds/, themes/
starship/starship.toml      prompt
shell/init.sh               the one file bash and zsh load (common.sh, direnv, starship, tools)
shell/common.sh             personal aliases, PATH, env, dex, nvm (both shells)
shell/inputrc               bash key settings
zsh/zshrc                   zsh setup
install.sh / uninstall.sh   set up / remove, per component
bootstrap.sh                the one-command install (clone or pull, add layers, run install.sh)
```
