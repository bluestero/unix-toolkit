"""tk update and install.sh run twice, on scratch git repos: the toolkit (a copy of this one)
and a "demo" layer whose v2 renames a command (old-name -> new-name), removes a part
(demo-gone) and adds one (demo-fresh). Both are clones of bare repos in the sandbox, so
tk update really pulls. Scratch HOME; nothing here reaches the real machine."""
import os
import re
import shutil
import subprocess

from fixture import REPO
from term import Term

GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
           "GIT_COMMITTER_EMAIL": "t@t", "WORK_TOOLKIT_PLAIN": "1"}


def part(pid, cmd):
    """A layer part that links ~/.local/bin/<cmd> to the layer's bin/<cmd>."""
    f = pid.replace("-", "_")
    src = f'"$repo/layers/demo/bin/{cmd}"'
    return f"""
group_{f}() {{ echo Demo; }}
label_{f}() {{ echo "{pid}"; }}
title_{f}() {{ echo "the {cmd} command"; }}
detail_{f}() {{ echo "~/.local/bin/{cmd}"; }}
state_{f}() {{ NOTE=""; if linked ~/.local/bin/{cmd} {src}; then STATE=installed; else STATE=missing; fi; }}
install_{f}() {{ linked ~/.local/bin/{cmd} {src} && return; ask "Link {cmd}?" && link_file ~/.local/bin/{cmd} {src} || skip; }}
uninstall_{f}() {{ unlink_file ~/.local/bin/{cmd} {src}; }}
"""


def git(sb, *args, cwd):
    subprocess.run(["git", *args], cwd=cwd, env=sb.env, check=True, capture_output=True)


def write_layer(d, parts, same="v1"):
    shutil.rmtree(os.path.join(d, "bin"), ignore_errors=True)
    os.makedirs(os.path.join(d, "bin"))
    for _, cmd in parts:
        p = os.path.join(d, "bin", cmd)
        open(p, "w").write("#!/bin/sh\necho " + cmd + (" " + same if cmd == "same-cmd" else "") + "\n")
        os.chmod(p, 0o755)
    ids = " ".join(pid for pid, _ in parts)
    open(os.path.join(d, "components.sh"), "w").write(
        f"COMPONENTS+=({ids})\n" + "".join(part(pid, cmd) for pid, cmd in parts))


def world(sb):
    """The toolkit and the demo layer (v1) cloned from bare repos; returns the toolkit folder."""
    sb.env.update(GIT_ENV)
    r = sb.root
    shutil.copytree(REPO, r + "/tk-src", ignore=shutil.ignore_patterns(".git", "layers", "tests", "tasks", "*.zip"))
    git(sb, "init", "-q", "-b", "main", cwd=r + "/tk-src")
    git(sb, "add", "-A", cwd=r + "/tk-src")
    git(sb, "commit", "-qm", "toolkit", cwd=r + "/tk-src")
    git(sb, "clone", "-q", "--bare", "tk-src", "tk.git", cwd=r)
    git(sb, "clone", "-q", "tk.git", "repo", cwd=r)
    os.makedirs(r + "/demo-src")
    write_layer(r + "/demo-src", [("demo-tool", "old-name"), ("demo-gone", "gone-cmd"), ("demo-same", "same-cmd")])
    git(sb, "init", "-q", "-b", "main", cwd=r + "/demo-src")
    git(sb, "add", "-A", cwd=r + "/demo-src")
    git(sb, "commit", "-qm", "v1", cwd=r + "/demo-src")
    git(sb, "clone", "-q", "--bare", "demo-src", "demo.git", cwd=r)
    git(sb, "clone", "-q", r + "/demo.git", "layers/demo", cwd=r + "/repo")
    return r + "/repo"


def push_v2(sb):
    """Upstream: old-name renamed to new-name, demo-gone removed, demo-fresh added, same-cmd edited."""
    d = sb.root + "/demo-src"
    write_layer(d, [("demo-tool", "new-name"), ("demo-fresh", "fresh-cmd"), ("demo-same", "same-cmd")], same="v2")
    git(sb, "add", "-A", cwd=d)
    git(sb, "commit", "-qm", "v2", cwd=d)
    git(sb, "push", "-q", sb.root + "/demo.git", "main", cwd=d)


def push_toolkit(sb):
    """Upstream toolkit: one new commit (a note in the README)."""
    d = sb.root + "/tk-src"
    with open(d + "/README.md", "a") as fh:
        fh.write("\nnew\n")
    git(sb, "commit", "-qam", "toolkit v2", cwd=d)
    git(sb, "push", "-q", sb.root + "/tk.git", "main", cwd=d)


def head(sb, d):
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=d, env=sb.env, capture_output=True, text=True).stdout


def pick(sb, repo, *keys):
    """tk update up to its repo list, then the keys; returns the terminal."""
    t = Term([repo + "/bin/tk", "update"], sb.env, cols=140, rows=34, cwd=sb.home)
    t.wait_for("pull which?", timeout=60)
    t.settle()
    if keys:
        t.key(*keys)
    return t


def run(sb, *args):
    p = subprocess.run([*args], env=sb.env, cwd=sb.home, capture_output=True, text=True, timeout=120,
                       stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout + p.stderr


def bin_links(sb):
    d = sb.path("~/.local/bin")
    return {n: os.readlink(os.path.join(d, n)) for n in sorted(os.listdir(d))} if os.path.isdir(d) else {}


def snapshot(sb):
    """Every file under HOME: a link's target, a file's text (the log left out: it grows by design)."""
    out = {}
    for root, dirs, files in os.walk(sb.home):
        for n in dirs + files:
            p = os.path.join(root, n)
            rel = os.path.relpath(p, sb.home)
            if rel.endswith("setup.log"):
                continue
            if os.path.islink(p):
                out[rel] = "-> " + os.readlink(p)
            elif os.path.isfile(p):
                out[rel] = open(p, "rb").read()
    return out


def set_up_v1(sb):
    repo = world(sb)
    code, out = run(sb, repo + "/install.sh", "--yes", "demo-tool", "demo-gone", "demo-same")
    assert code == 0, out
    assert set(bin_links(sb)) == {"old-name", "gone-cmd", "same-cmd"}, bin_links(sb)
    return repo


def test_update_shows_where_things_stand(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    t = pick(sb, repo)
    assert "demo" in t.text() and "1 new commit" in t.text() and "update and" not in t.text(), t.text()
    t.key("enter")                                               # all ticked: pull them
    t.wait_for("Summary", timeout=60)
    t.settle()
    screen = t.text()
    assert "needs a fix" in screen and "removed upstream" in screen and "○ new" in screen, screen
    assert re.search(r"demo-same\s+✓ updated", screen), screen  # its file changed: nothing to do
    assert "Summary · 2 to set up" in screen, screen             # the fix and the cleanup; the new part isn't ticked
    t.key("esc")
    t.wait_exit()
    assert set(bin_links(sb)) == {"old-name", "gone-cmd", "same-cmd"}, "esc must change nothing"


def test_update_fixes_the_rename_and_cleans_up(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    code, out = run(sb, repo + "/bin/tk", "update", "--yes")
    assert code == 0, out
    links = bin_links(sb)
    assert set(links) == {"new-name", "same-cmd"}, (links, out)              # renamed: new link, the dead ones gone
    assert links["new-name"].endswith("/layers/demo/bin/new-name")
    assert "fresh-cmd" not in links                              # a new part is offered, never set up unasked


def test_update_twice_changes_nothing_the_second_time(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    code, out = run(sb, repo + "/bin/tk", "update", "--yes")
    assert code == 0, out
    before = snapshot(sb)
    code, out = run(sb, repo + "/bin/tk", "update", "--yes")
    assert code == 0, out
    assert "already up to date" in out and "Nothing to do" in out, out
    assert snapshot(sb) == before


def test_update_without_a_terminal_pulls_nothing(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    before = head(sb, repo + "/layers/demo")
    code, out = run(sb, repo + "/bin/tk", "update")
    assert code == 0, out
    assert "demo" in out and "1 new commit" in out and "in a terminal" in out and "• v2" in out, out
    assert head(sb, repo + "/layers/demo") == before, "nothing pulled without asking"
    assert set(bin_links(sb)) == {"old-name", "gone-cmd", "same-cmd"}   # nothing changed


def test_held_back_repo_stays_where_it_was(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    push_toolkit(sb)
    tk0, demo0 = head(sb, repo), head(sb, repo + "/layers/demo")
    t = pick(sb, repo)
    assert "layers may need the newer toolkit" in t.text(), t.text()
    t.key("down", "tab", "enter")                                # untick demo (second row), pull the toolkit
    assert t.wait_exit() == 0                                    # (the toolkit's pull changes no part: nothing to ask)
    assert "demo: not pulled" in t.text(), t.text()
    assert head(sb, repo) != tk0, "the toolkit was ticked: pulled"
    assert head(sb, repo + "/layers/demo") == demo0, "demo was unticked: left as it was"


def test_esc_on_the_repo_list_pulls_nothing(sb):
    repo = set_up_v1(sb)
    push_v2(sb)
    demo0 = head(sb, repo + "/layers/demo")
    t = pick(sb, repo, "esc")
    assert t.wait_exit() == 0
    assert "Nothing pulled" in t.text(), t.text()
    assert head(sb, repo + "/layers/demo") == demo0


def test_install_twice_gives_the_same_result(sb):
    repo = world(sb)
    sb.fake("yazi", "exit 0")
    sb.write("~/.bashrc", "export FOO=1\n")
    parts = ["bash", "keys", "commands", "yazi-keys", "claude-hook", "claude-guard", "demo-tool"]
    os.makedirs(sb.path("~/.claude"))
    sb.env["CLAUDE_CONFIG_DIR"] = sb.path("~/.claude")
    code, out = run(sb, repo + "/install.sh", "--yes", *parts)
    assert code == 0, out
    first = snapshot(sb)
    code, out = run(sb, repo + "/install.sh", "--yes", *parts)
    assert code == 0, out
    assert snapshot(sb) == first, sorted(set(snapshot(sb)) ^ set(first))
    assert "Everything is already set up" in out, out
