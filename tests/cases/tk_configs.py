"""tk configs: one list of the apps the toolkit configures; the choices and the question
open in it. Uses btop's config in the scratch HOME (the repo's btop.conf isn't written)."""
import os

from fixture import REPO
from term import Term

TK = os.path.join(REPO, "bin/tk")
CONF = "~/.config/btop/btop.conf"


def start(sb):
    sb.fake("btop", "exit 0")
    t = Term([TK, "configs"], sb.env)
    t.wait_for("btop")
    t.settle()
    t.key("btop")
    t.settle()
    t.key("enter")
    t.wait_for("now uses")
    t.settle()
    return t


def pick(t, choice):
    for _ in range(6):
        if choice in (t.cursor_line() or ""):
            break
        t.key("down")
    else:
        raise AssertionError(f"the cursor never reached {choice!r}")
    t.key("enter")


def test_own_file_to_default_asks_then_undo_brings_it_back(sb):
    sb.write(CONF, "mine = 1\n")
    t = start(sb)
    t.wait_for("your own file")
    pick(t, "App's default")
    t.wait_for("This replaces your own")
    t.key("y")
    t.wait_for("the app's default")
    assert t.alive(), "the list stays open"
    assert not os.path.lexists(sb.path(CONF)), "the app's default: no config file"
    t.settle()
    t.key("enter")                                   # btop again (the cursor stays on it)
    t.wait_for("Undo the last change")
    t.settle()
    pick(t, "Undo the last change")
    t.wait_for("back to before the last change")
    assert sb.read(CONF) == "mine = 1\n", "undo puts your own file back"


def test_own_file_no_changes_nothing(sb):
    sb.write(CONF, "mine = 1\n")
    t = start(sb)
    pick(t, "App's default")
    t.wait_for("This replaces your own")
    t.key("n")
    t.wait_for("Nothing changed")
    assert sb.read(CONF) == "mine = 1\n"


def test_default_to_preset_gives_btop_a_file_of_its_own(sb):
    t = start(sb)
    t.wait_for("app's default")
    pick(t, "Toolkit preset")
    t.wait_for("toolkit preset")
    conf = sb.path(CONF)
    assert not os.path.islink(conf), "btop writes its config: a file of its own, not a link into the repo"
    assert open(conf).read().strip() == open(os.path.join(REPO, "btop/btop.conf")).read().strip()


def test_btop_menu_changes_kept_as_my_patch(sb):
    preset = open(os.path.join(REPO, "btop/btop.conf")).read()
    assert "\nrounded_corners = True" in preset
    t = start(sb)
    pick(t, "Toolkit preset")
    t.wait_for("toolkit preset")
    conf = sb.path(CONF)
    with open(conf, "w") as f:                       # what btop's menu does
        f.write(preset.replace("\nrounded_corners = True", "\nrounded_corners = False"))
    t.settle()
    t.key("esc")                                     # leave and come back: the list reads it again
    t.wait_exit()
    t = start(sb)
    t.wait_for("edited preset")
    pick(t, "Keep these changes as my patch")
    t.wait_for("This replaces the changes made in btop")
    t.key("y")
    t.wait_for("your patch now")
    t.wait_for("+ my patch")
    assert "rounded_corners = False" in sb.read("~/.config/work-toolkit/patches/btop.conf")
    assert "rounded_corners = False" in open(conf).read(), "btop keeps the change"


def test_esc_goes_back_then_closes(sb):
    t = start(sb)
    t.key("esc")
    t.wait_for("esc close")
    assert t.alive()
    t.key("esc")
    assert t.wait_exit() == 0


KITTY = "~/.config/kitty/kitty.conf"
PATCH = "~/.config/work-toolkit/patches/kitty.conf"


def start_kitty(sb):
    """kitty on the toolkit's preset (a link into the repo, which the test never writes)."""
    os.makedirs(sb.path("~/.config/kitty"))
    os.symlink(os.path.join(REPO, "kitty/kitty.conf"), sb.path(KITTY))
    t = Term([TK, "configs"], sb.env)
    t.wait_for("kitty")
    t.settle()
    t.key("kitty")
    t.settle()
    t.key("enter")
    t.wait_for("now uses")
    t.settle()
    return t


def test_edit_my_patch_starts_from_the_preset(sb):
    sb.fake("myedit", 'echo "font_size 15" >>"$1"')
    sb.env["VISUAL"] = "myedit"
    t = start_kitty(sb)
    pick(t, "Edit my patch")
    t.wait_for("your patch saved")
    t.wait_for("+ my patch")
    text = sb.read(PATCH)
    assert text.startswith("# Your patch for kitty"), text[:200]
    assert "# globinclude theme.conf" in text, "the preset is in it, as comments"
    assert text.rstrip().endswith("font_size 15"), "what the editor wrote stays"
    assert os.path.realpath(sb.path(KITTY)) == os.path.join(REPO, "kitty/kitty.conf"), "the preset stays linked"


def test_drop_my_patch_keeps_a_copy(sb):
    sb.write(PATCH, "font_size 15\n")
    t = start_kitty(sb)
    t.wait_for("+ my patch")
    pick(t, "Drop my patch")
    t.wait_for("Drop your kitty patch?")
    t.key("y")
    t.wait_for("patch dropped")
    assert not os.path.exists(sb.path(PATCH))
    assert sb.read(PATCH + ".dropped") == "font_size 15\n"


STAR = "~/.config/starship.toml"
MERGED = "~/.local/state/work-toolkit/starship.toml"


def start_starship(sb, edit):
    sb.fake("starship", "exit 0")
    sb.fake("myedit", edit)
    sb.env["VISUAL"] = "myedit"
    os.makedirs(sb.path("~/.config"), exist_ok=True)
    os.symlink(os.path.join(REPO, "starship/starship.toml"), sb.path(STAR))
    t = Term([TK, "configs"], sb.env)
    t.wait_for("starship")
    t.settle()
    t.key("enter")                                   # starship is the first row
    t.wait_for("now uses")
    t.settle()
    pick(t, "Edit my patch")
    return t


def test_starship_patch_is_merged_over_the_preset(sb):
    t = start_starship(sb, 'printf "\\n[git_branch]\\nstyle = \\"fg:#ff0000\\"\\n" >>"$1"')
    t.wait_for("your patch saved")
    text = sb.read(MERGED)
    assert 'style = "fg:#ff0000"' in text, text
    assert 'format = "[$branch]($style)"' in text, "the rest of [git_branch] stays the preset's"
    assert os.path.realpath(sb.path(STAR)) == os.path.join(REPO, "starship/starship.toml")


def test_starship_broken_patch_says_so(sb):
    t = start_starship(sb, 'echo "oops =" >>"$1"')
    t.wait_for("your patch has an error")
    assert t.alive()
