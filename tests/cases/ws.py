"""ws: without Window Calls, ctrl-x asks in the list (fake gdbus fails, so it's "missing")."""
import os

from term import Term
from worlds import WS


def start(sb):
    for name in ("alpha", "beta"):
        os.makedirs(sb.path(f"~/code/{name}"))
    sb.write("~/.config/ws/workspaces", "~/code/alpha\n~/code/beta\n")
    sb.env["WS_EDITOR"] = "code"
    t = Term([WS], sb.env)
    t.wait_for("workspace>")
    t.wait_for("beta")
    t.settle()
    return t


def test_ctrl_x_asks_then_no_keeps_the_list(sb):
    t = start(sb)
    t.key("ctrl-x")
    t.wait_for("Window Calls. Install it now?")
    assert "beta" in t.text(), "the list should stay visible under the question"
    t.key("n")
    t.wait_gone("Install it now?")
    t.key("b")
    t.wait(lambda t: "alpha" not in t.text(), what="typing to filter the list again")
    assert t.alive()
    t.key("esc")
    t.wait_exit()
    assert sb.calls("code") == [], "nothing should have opened"


def test_esc_quits(sb):
    t = start(sb)
    t.key("esc")
    assert t.wait_exit() == 0
