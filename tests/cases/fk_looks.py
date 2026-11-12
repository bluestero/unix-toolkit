"""fk looks (feelkit layer): one list; the choices and the reset question open in it.
dconf and gsettings are fakes: no real setting is read or changed."""
import os

from term import Term
from worlds import FK

VITALS = "Vitals@CoreCoding.com"
VITALS_PATH = "/org/gnome/shell/extensions/vitals/"


def skip():
    if not os.path.exists(FK):
        return "the feelkit layer isn't in layers/feelkit"


def start(sb):
    os.makedirs(sb.path(f"~/.local/share/gnome-shell/extensions/{VITALS}"))
    sb.write(sb.fix + "/enabled-extensions", f"['{VITALS}']\n")
    t = Term([FK, "looks"], sb.env)
    t.wait_for("Vitals")
    t.settle()
    return t


def resets(sb):
    return [c for c in sb.calls("dconf") if c.startswith(f"dconf reset -f {VITALS_PATH}")]


def open_reset(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Reset to the app's defaults")
    t.settle()
    for _ in range(6):
        if "Reset to the app's defaults" in (t.cursor_line() or ""):
            break
        t.key("down")
    else:
        raise AssertionError("the cursor never reached \"Reset to the app's defaults\"")
    t.key("enter")
    t.wait_for("Reset Vitals to the app's defaults?")
    return t


def test_enter_shows_the_choices_and_esc_goes_back(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Keep my settings")
    t.wait_for("Re-apply the toolkit look")
    t.key("esc")
    t.wait_gone("Keep my settings")
    t.wait_for("esc close")
    assert t.alive(), "esc on the choices goes back to the list"
    t.key("esc")
    code = t.wait_exit()
    assert code == 0, f"esc should close it cleanly, exit code {code}"


def test_reset_then_no_changes_nothing(sb):
    t = open_reset(sb)
    t.key("n")
    t.wait_for("Nothing changed")
    assert t.alive()
    assert resets(sb) == []


def test_reset_then_yes_resets(sb):
    t = open_reset(sb)
    t.key("y")
    t.wait_for("back to the app's defaults")
    assert t.alive()
    assert len(resets(sb)) == 1, sb.calls("dconf")


def test_keep_changes_nothing(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Keep my settings")
    t.settle()
    t.key("enter")
    t.wait_for("settings kept")
    assert [c for c in sb.calls("dconf") if not c.startswith("dconf dump")] == []


def test_keep_my_changes_as_my_patch(sb):
    preset = open(os.path.join(os.path.dirname(os.path.dirname(FK)), "gnome/vitals/settings.dconf")).read()
    assert "hide-zeros=false" in preset
    sb.write(sb.fix + "/dump", preset.replace("hide-zeros=false", "hide-zeros=true"))
    sb.fake("dconf", '[ "$1" = dump ] && cat "$TK_FIX/dump"; exit 0')
    t = start(sb)
    t.wait_for("your own settings")
    t.key("enter")
    t.wait_for("Keep my changes as my patch")
    t.settle()
    for _ in range(8):
        if "Keep my changes as my patch" in (t.cursor_line() or ""):
            break
        t.key("down")
    t.key("enter")
    t.wait_for("your patch now")
    t.wait_for("+ my patch")
    assert sb.read(f"~/.config/work-toolkit/patches/{VITALS}.dconf").strip() == "[/]\nhide-zeros=true"
