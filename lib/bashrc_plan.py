"""Print the cleaned-up ~/.bashrc on stdout. install.sh diffs it against the real one.

    python3 -I lib/bashrc_plan.py <bashrc> <init_line>

Takes out everything the toolkit now provides (shell/common.sh, shell/init.sh and
the tools), plus leftovers that would clash with it: ble.sh, old okcli hooks,
the old twinconnect / k-icon functions, duplicate nvm and direnv/starship lines.
Then makes sure the one init line is there, pointing at this repo.
Running it on its own output changes nothing.
"""
import os
import re
import sys

path, init_line = sys.argv[1], sys.argv[2]
s = open(path).read()


def cut(text, start_pat, end_pat):
    """Remove every block from a line matching start_pat to the next line matching end_pat."""
    while True:
        m = re.search(start_pat, text, re.M)
        if not m:
            return text
        m2 = re.search(end_pat, text[m.end():], re.M)
        if not m2:
            return text
        e = m.end() + m2.end()
        if e < len(text) and text[e] == "\n":
            e += 1
        text = text[: m.start()] + text[e:]


def drop_lines(text, *patterns):
    for pat in patterns:
        text = re.sub(r"^" + pat + r"[ \t]*\n", "", text, flags=re.M)
    return text


# ble.sh (tried and removed)
s = cut(s, r"^# >>> ble\.sh.*\n", r"^# <<< ble\.sh.*$")
s = drop_lines(s, r".*blesh/ble\.sh.*", r".*\bble-attach\b.*")

# Okta settings -> okta/shell/okta-env.sh
s = re.sub(r"^# Okta Config\n(?:export OKTA_AWSCLI_[A-Z_]+=.*\n)+", "", s, flags=re.M)
s = drop_lines(s, r"export OKTA_AWSCLI_[A-Z_]+=.*", r"# alias okcli=.*",
               r"# replaced by okcli .*alias okcli=.*")
# Old okcli hook lines (any path) -> shell/init.sh loads it
s = drop_lines(s, r'\[ -f "[^"]*/okta/shell/okcli\.sh" \].*# okcli')

# twinconnect -> twin, k-icon -> kitty/shell/k-icon.sh
s = cut(s, r"^# Twingate exit-node connect and switch\n", r"^}$")
s = cut(s, r"^twinconnect\(\) \{\n", r"^}$")
s = cut(s, r"^# >>> Kitty Icon Picker >>>", r"^# <<< Kitty Icon Picker <<<$")

# Personal aliases, PATH, env, dex, nvm -> shell/common.sh
# An alias goes only when it's exactly the one shell/common.sh has (a copy of the
# toolkit's). Your own alias by the same name stays, and wins: common.sh never
# overrides an alias you already have.
common = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell", "common.sh")
toolkit_aliases = set()
for line in open(common):
    m = re.match(r"\s*_work_alias\s+([A-Za-z0-9_-]+)\s+'(.*)'\s*$", line)
    # the ones that moved out of ~/.bashrc (Ubuntu's ls/ll/alert lines stay where they are)
    if m and m.group(1) in {"venv", "pushcreds", "gcb", "pyclean", "nb", "lb", "cb"}:
        toolkit_aliases.add(f"alias {m.group(1)}='{m.group(2)}'")
s = "".join(l for l in s.splitlines(keepends=True) if l.strip() not in toolkit_aliases)
s = drop_lines(
    s,
    r"# Custom aliases",
    r'export PATH="?\$HOME/(\.local/)?bin:\$PATH"?',
    r"# Bash related configs and hooks",
    r"# Claude: work account by default.*",
    r"# \(only if unset, so nested shells keep what direnv already applied\)",
    r'export CLAUDE_CONFIG_DIR="\$\{CLAUDE_CONFIG_DIR:-\$HOME/\.claude-profiles/work\}"',
    r"# Docker container function",
    r"# NVM Configuration",
    r'export NVM_DIR="\$HOME/\.nvm"',
    r'\[ -s "\$NVM_DIR/(nvm\.sh|bash_completion|nvm_completion)" \] && \\?\. "\$NVM_DIR/[a-z_.]+".*',
)
s = cut(s, r"^(function dex \{|dex\(\) \{)\n", r"^}$")

# direnv and starship hooks -> shell/init.sh (it loads them in the right order)
s = drop_lines(s, r'eval "\$\(direnv hook bash\)"', r'eval "\$\(starship init bash\)"')

# The init line: keep it where it is (fixing the path if the repo moved), or add it.
init_re = r'^\[ -f "[^"]*/shell/init\.sh" \] && \. "[^"]*/shell/init\.sh".*# work toolkit.*$'
if re.search(init_re, s, flags=re.M):
    first = [True]

    def keep_first(_m):
        if first[0]:
            first[0] = False
            return init_line
        return ""

    s = re.sub(init_re, keep_first, s, flags=re.M)
else:
    s = s.rstrip("\n") + "\n\n" + init_line + "\n"

s = re.sub(r"\n{3,}", "\n\n", s).rstrip("\n") + "\n"
sys.stdout.write(s)
