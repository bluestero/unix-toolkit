"""yazi keys (yazi/keymap.toml) in a real yazi with a scratch config: > jumps to a folder
picked with fzf; alt+backspace (what kitty sends for ctrl+backspace) deletes a word."""
import os
import shutil

from fixture import REPO
from term import Term


def skip():
    if not shutil.which("yazi"):
        return "yazi isn't installed"


def start(sb):
    cfg = sb.root + "/yazi"
    os.makedirs(cfg)
    shutil.copy(os.path.join(REPO, "yazi/keymap.toml"), cfg + "/keymap.toml")
    tree = sb.path("~/tree")
    for d in ("alpha/deep/needle", "beta", ".hidden/needle2"):
        os.makedirs(os.path.join(tree, d))
    sb.env["YAZI_CONFIG_HOME"] = cfg
    sb.env["SHELL"] = "/bin/sh"
    t = Term(["yazi", "--cwd-file=" + sb.root + "/cwd"], sb.env, cwd=tree)
    t.wait_for("alpha")
    t.settle()
    return t, tree


def test_greater_than_jumps_to_a_folder_inside(sb):
    t, tree = start(sb)
    t.key(">")
    t.wait_for("folder>")
    assert ".hidden" not in t.text(), "hidden folders aren't offered"
    t.key("needle")
    t.wait(lambda t: "alpha/deep/needle" in t.text() and "beta" not in t.text(), what="the filter to narrow")
    t.key("enter")
    t.wait_gone("folder>")
    t.settle()
    t.key("q")
    t.wait_exit()
    assert open(sb.root + "/cwd").read().strip() == os.path.join(tree, "alpha/deep/needle")


def test_alt_backspace_deletes_a_word(sb):
    t, _ = start(sb)
    t.key("f")                                   # yazi's filter box
    t.settle()
    t.key("abc def")
    t.wait_for("abc def")
    t.key("alt-bs")
    t.wait_gone("abc def")
    assert "abc" in t.text()
    t.key("esc", gap=0.4)                        # yazi's input: insert → normal mode
    t.key("esc")
    t.wait_gone("Filter:")                       # esc then q at once would be alt+q
    t.key("q")
    t.wait_exit()
