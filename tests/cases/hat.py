"""hat: its panel asks in the list; a wrong typed answer comes back with the reason."""
import os

from term import Term
from worlds import HAT


def start(sb):
    proj = sb.path("~/code/proj")
    os.makedirs(proj)
    t = Term([HAT], sb.env, cwd=proj)
    t.wait_for("~/code/proj")
    t.settle()
    return t


def test_add_a_folder_that_isnt_there_asks_again(sb):
    t = start(sb)
    t.key("alt-a")
    t.wait_for("Folder to give a hat?")
    t.key("ctrl-u", "/nowhere-xyz", "enter")
    t.wait_for("there's no folder")
    assert "/nowhere-xyz" in (t.line_with("folder:") or ""), "the typed text should be kept to fix"
    t.key("esc")
    t.wait_gone("Folder to give a hat?")
    assert t.alive(), "esc on the question goes back to the list"
    t.key("esc")
    assert t.wait_exit() == 0


def test_quit_with_unsaved_change_asks(sb):
    sb.write("~/.aws/config", "[profile shop-dev]\n[profile shop-prod]\n")
    t = start(sb)
    t.key("alt-right", "alt-right")              # to the AWS column
    t.settle()
    t.key("right")                               # change it
    t.wait_for("shop-")
    t.settle()
    t.key("esc")
    t.wait_for("Quit and drop 1 unsaved change?")
    t.key("n")
    t.wait_gone("Quit and drop 1 unsaved change?")
    assert t.alive(), "no keeps the panel open"
    t.key("esc")
    t.wait_for("Quit and drop 1 unsaved change?")
    t.key("y")
    assert t.wait_exit() == 0
    assert not os.path.exists(sb.path("~/code/proj/.envrc")), "nothing should have been saved"
