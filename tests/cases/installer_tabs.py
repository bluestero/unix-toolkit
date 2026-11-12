"""./install.sh's tab view, in a scratch copy of the repo (feelkit included: a standalone
layer, so only fk install / --layer=feelkit shows it) with a scratch HOME and a fake GNOME.
Nothing is set up: each test stops at the first question of the run, or before."""
import os
import re
import shutil
import subprocess

from fixture import REPO
from term import Term

TABS = ["Recommended", "Kitty", "Optional", "Desktop (GNOME)", "Cloud", "Workspaces", "Claude Code"]


def copy(sb):
    dst = sb.root + "/repo"
    shutil.copytree(REPO, dst, ignore=shutil.ignore_patterns(".git", "tests", "tasks", "airpr", "*.zip"))
    sb.fake("gnome-shell", "exit 0")
    return dst


def start(sb, *args):
    repo = copy(sb)
    t = Term([repo + "/install.sh", *args], sb.env, cols=120, rows=34, cwd=sb.home)
    t.wait_for("enter to the summary", timeout=20)
    t.settle()
    return repo, t


def test_every_component_is_on_a_tab(sb):
    repo, t = start(sb)
    seen = set()
    for _ in TABS:
        seen |= set(re.findall(r"^│ . (?:\[.\]|   )\s+(\S+)\s+[○✓◐⊘–] ", t.text(), re.M))
        t.key("right")
        t.settle()
    t.key("esc")
    t.wait_exit()
    ls = subprocess.run([repo + "/install.sh", "ls"], env=sb.env, cwd=sb.home, capture_output=True, text=True,
                        stdin=subprocess.DEVNULL, timeout=60).stdout
    every = set(re.findall(r"^  (\S+)\s", ls, re.M)) - {"COMPONENT"}
    assert every and every == seen, (every ^ seen)


def test_esc_changes_nothing(sb):
    _, t = start(sb)
    t.key("tab", "right", "enter")
    t.wait_for("SETS UP")
    t.key("esc")
    assert t.wait_exit() == 0
    assert "Nothing changed" in t.text()
    assert not os.path.exists(sb.path("~/.bashrc")) and not os.path.exists(sb.path("~/.local/bin"))


def test_nothing_starts_ticked(sb):
    _, t = start(sb)
    assert "Summary · nothing ticked" in t.text() and "[✓]" not in t.text(), t.text()
    t.key("enter")
    t.wait_for("Nothing ticked")
    t.key("enter")                                        # enter with nothing ticked: leaves, nothing changed
    assert t.wait_exit() == 0
    assert "Nothing picked" in t.text()


def test_tick_follows_to_the_summary(sb):
    _, t = start(sb)
    t.key("down", "tab")                                # keys, the second row
    t.wait_for("Summary · 1 to set up")
    t.key("enter")
    t.wait_for("✓ keys ")
    t.settle()
    assert "✓ bash " not in t.text(), "only keys was ticked"
    t.key("esc")
    t.wait_exit()


def run(sb, repo, *args):
    p = subprocess.run([repo + "/" + args[0], *args[1:]], env=sb.env, cwd=sb.home, capture_output=True,
                       text=True, stdin=subprocess.DEVNULL, timeout=60)
    return p.returncode, p.stdout + p.stderr


def test_feelkit_stays_out_of_the_main_install(sb):
    repo = copy(sb)
    _, out = run(sb, repo, "install.sh", "ls")
    assert "kitty-bg" not in out and "dash2dock" not in out and "kitty-config" in out, out
    code, out = run(sb, repo, "install.sh", "kitty-bg")
    assert code == 2 and "fk install kitty-bg" in out, out
    code, out = run(sb, repo, "uninstall.sh", "kitty-bg")
    assert code == 2 and "fk uninstall kitty-bg" in out, out
    _, out = run(sb, repo, "install.sh", "--layer=feelkit", "ls")
    rows = set(re.findall(r"^  (\S+) ", out, re.M))
    assert "kitty-bg" in rows and "kitty-config" not in rows, out


def test_both_bars_ask_and_no_goes_back(sb):
    _, t = start(sb, "--layer=feelkit")
    t.key("right")                                        # GNOME looks: dash2dock, dash-to-panel first
    t.wait(lambda t: "dash2dock" in t.cursor_line(), what="the cursor on dash2dock")
    t.key("tab", "down", "tab")
    t.wait_for("Summary · 2 to set up")
    t.key("enter")
    t.wait_for("SETS UP")
    t.key("enter")
    t.wait_for("Both bars use the same space. Keep both?")
    t.key("n")
    t.wait_gone("Keep both?")
    t.wait(lambda t: "dash2dock" in t.cursor_line() and "[✓]" in t.cursor_line(),
           what="back on the GNOME looks tab, on dash2dock, still ticked")
    t.key("esc")
    assert t.wait_exit() == 0
    assert not os.path.exists(sb.path("~/.bashrc"))


def test_both_bars_yes_sets_up(sb):
    _, t = start(sb, "--plain", "--layer=feelkit")
    t.key("right")                                        # GNOME looks: dash2dock, dash-to-panel first
    t.wait(lambda t: "dash2dock" in t.cursor_line(), what="the cursor on dash2dock")
    t.key("tab", "down", "tab")
    t.wait_for("Summary · 2 to set up")
    t.key("enter")
    t.wait_for("SETS UP")
    t.key("enter")
    t.wait_for("Keep both?")
    t.key("y")
    t.wait_for("[y/N, default: no]")                      # the run has started: its first question
    t.close()


def test_enter_on_the_summary_sets_up_the_ticked(sb):
    _, t = start(sb, "--plain")
    t.key("tab")                                        # bash
    t.wait_for("Summary · 1 to set up")
    t.key("enter")
    t.wait_for("✓ bash ")
    t.key("enter")
    t.wait_for("[Y/n, default: yes]")                     # the run has started: its first question
    t.close()


def test_all_set_still_opens_the_tabs(sb):
    repo = copy(sb)
    os.makedirs(repo + "/layers/demo")
    with open(repo + "/layers/demo/components.sh", "w") as f:
        f.write('COMPONENTS+=(demo-part)\ngroup_demo_part() { echo Demo; }\n'
                'label_demo_part() { echo Demo; }; title_demo_part() { echo "a part that is in"; }\n'
                'detail_demo_part() { echo nothing; }; state_demo_part() { STATE=installed NOTE=""; }\n'
                'install_demo_part() { ok "already there"; }; uninstall_demo_part() { :; }\n')
    t = Term([repo + "/install.sh", "--layer=demo"], sb.env, cols=120, rows=34, cwd=sb.home)
    t.wait_for("Summary · all set", timeout=20)
    t.wait_for("demo-part")
    t.key("enter")
    t.wait_for("Everything here is set up")
    t.key("enter")
    assert t.wait_exit() == 0
    assert "Everything is already set up" in t.text()
