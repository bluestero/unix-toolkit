"""Speed (tasks/11): time from a key to the screen changing, and command start-up, each
against a budget. Run by name only (tests/run.sh speed); prints a table at the end.

Budgets (tasks/11): a key that moves or filters < 50 ms; a key that runs a callback
< 150 ms; a picker open < 300 ms; a command printing its list < 300 ms (this one is
our pick: task 11 gives none). Each number is the median of a few tries, in a sandbox
with fakes, so kubectl / aws time isn't in it.
"""
import os
import statistics
import subprocess
import time

from fixture import REPO
from term import Term
from worlds import FK, HAT, KX, OKCLI, WS, aws, kube

MOVE, CALLBACK, OPEN, COMMAND = 50, 150, 300, 300
RESULTS = []   # (what, ms, budget)


def record(what, secs, budget):
    ms = round(statistics.median(secs) * 1000)
    RESULTS.append((what, ms, budget))
    return ms


def check(*rows):
    over = [f"{w}: {ms} ms (budget {b})" for w, ms, b in rows if ms > b]
    assert not over, "over budget: " + " · ".join(over)


def report():
    if not RESULTS:
        return
    w = max(len(r[0]) for r in RESULTS)
    print(f"\n  {'what'.ljust(w)}   {'ms':>5}   budget")
    for what, ms, budget in RESULTS:
        mark = "✗" if ms > budget else "✓"
        print(f"  {what.ljust(w)}   {ms:>5}   {budget:>6}  {mark}")
    RESULTS.clear()


# ------------------------------------------------------------- set-ups
def okcli_world(sb):
    aws(sb)
    return [OKCLI], "profile>", None


def kx_world(sb):
    kube(sb)
    return [KX], "context>", None


def ws_world(sb):
    for name in ("alpha", "beta", "gamma"):
        os.makedirs(sb.path(f"~/code/{name}"))
    sb.write("~/.config/ws/workspaces", "~/code/alpha\n~/code/beta\n~/code/gamma\n")
    sb.env["WS_EDITOR"] = "code"
    return [WS], "workspace>", None


def hat_world(sb):
    os.makedirs(sb.path("~/code/proj"))
    return [HAT], "hat · folders", sb.path("~/code/proj")


def opened(sb, world, tries=3):
    cmd, ready, cwd = world(sb)
    secs = []
    for _ in range(tries):
        t0 = time.monotonic()
        t = Term(cmd, sb.env, cwd=cwd)
        t.wait_for(ready)
        secs.append(time.monotonic() - t0)
        t.settle()
        if _ < tries - 1:
            t.close()
    return t, secs


def to_row(t, text):
    """Put the pointer on the row showing text."""
    for k in ["up"] * 5 + ["down"] * 10:
        if text in (t.cursor_line() or ""):
            return
        t.key(k, gap=0.1)
    raise AssertionError(f"no row with {text!r}")


def picker(sb, world, name, question_key=None, question=None, row=None, move=("down", "up", "down", "up")):
    t, secs = opened(sb, world)
    rows = [(f"{name} · open", record(f"{name} · open", secs, OPEN), OPEN)]
    what = f"{name} · {' '.join(dict.fromkeys(move))}"
    secs = [t.timed_key(k) for k in move]
    rows.append((what, record(what, secs, MOVE), MOVE))
    t.settle(0.2)
    first = [t.timed_key("a")]
    rows.append((f"{name} · first filter key", record(f"{name} · first filter key", first, MOVE), MOVE))
    t.key("bs")
    t.settle(0.2)
    if question_key:
        if row:
            to_row(t, row)
            t.settle(0.2)
        what = f"{name} · {question_key} → question"
        secs = [t.timed_key(question_key, lambda t: question in t.flat())]
        rows.append((what, record(what, secs, CALLBACK), CALLBACK))
    t.close()
    check(*rows)


# ------------------------------------------------------------- pickers
def test_okcli(sb):
    picker(sb, okcli_world, "okcli", "enter", "Refresh now?", row="shop-dev")


def test_kx(sb):
    picker(sb, kx_world, "kx", "enter", "Refresh now?", row="shop-dev")


def test_ws(sb):
    picker(sb, ws_world, "ws", "ctrl-x", "Install it now?")


def test_hat(sb):
    picker(sb, hat_world, "hat", "alt-a", "Folder to give a hat?",
           move=("alt-right", "alt-left", "alt-right", "alt-left"))   # one folder: columns move


def test_fk_looks(sb):
    if not os.path.exists(FK):
        return
    vitals = "Vitals@CoreCoding.com"
    os.makedirs(sb.path(f"~/.local/share/gnome-shell/extensions/{vitals}"))
    sb.write(sb.fix + "/enabled-extensions", f"['{vitals}']\n")
    t, secs = opened(sb, lambda sb: ([FK, "looks"], "Vitals", None))
    rows = [("fk looks · open", record("fk looks · open", secs, OPEN), OPEN)]
    enter = [t.timed_key("enter", lambda t: "Keep my settings" in t.text())]
    rows.append(("fk looks · enter → choices", record("fk looks · enter → choices", enter, CALLBACK), CALLBACK))
    t.close()
    check(*rows)


# ------------------------------------------------------------- commands
def test_commands(sb):
    aws(sb)
    kube(sb)
    os.makedirs(sb.path("~/code/alpha"))
    sb.write("~/.config/ws/workspaces", "~/code/alpha\n")
    cmds = [("okcli ls", [OKCLI, "ls"]), ("kx ls", [KX, "ls"]), ("ws ls", [WS, "ls"]),
            ("hat ls", [HAT, "ls"]), ("tk ls", [f"{REPO}/bin/tk", "ls"]), ("ctx", [f"{REPO}/bin/ctx"])]
    if os.path.exists(FK):
        cmds.append(("fk help", [FK, "help"]))
    rows = []
    for name, cmd in cmds:
        secs = []
        for _ in range(3):
            t0 = time.monotonic()
            subprocess.run(cmd, env=sb.env, cwd=sb.home, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            secs.append(time.monotonic() - t0)
        rows.append((name, record(name, secs, COMMAND), COMMAND))
    check(*rows)
