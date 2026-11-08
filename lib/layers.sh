# Layers: extra parts kept in their own repos and cloned into layers/<name>/
# (tk layer add <git-url>; layers/ is gitignored). The toolkit finds them; there
# is nothing to register. A layer can have any of these, all optional:
#
#   bin/              its commands, put on PATH
#   shell/init.sh     sourced by every shell (bash and zsh) before the tools load:
#                     settings the tools read (OKTA_AWSCLI_*, KX_ALIAS_RULES, ...), aliases
#   components.sh     installer components: COMPONENTS+=(id ...), the usual
#                     label_/title_/detail_/state_/install_/uninstall_ functions,
#                     group_<id> to name its group (its installer tab), and
#                     GROUP_ABOUT[<group>]="one line" for a group of its own
#   tools             lines for tk:  name|group|what it does|program it needs
#   workspaces        a shared ws list; "@<name>" in your own list brings it in
#   claude/skills/*/  Claude Code skills, linked by the claude-skill component
#
# layer_dirs <toolkit root>: one layer folder per line, sorted by name
layer_dirs() {
  local d
  for d in "$1"/layers/*/; do [[ -d $d ]] && printf '%s\n' "${d%/}"; done
  return 0
}
# layer_path <toolkit root> <name>: that layer's folder; 1 when there is none
layer_path() { [[ -d $1/layers/$2 ]] && printf '%s\n' "$1/layers/$2"; }
