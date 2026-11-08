"""install.sh / uninstall.sh for the yazi-keys component, run for real but in a scratch
copy of the repo with a scratch HOME (never the real ones: see tasks/tasks.md)."""
import shutil
import subprocess

from fixture import REPO

START, END = "# >>> work toolkit >>>", "# <<< work toolkit <<<"
MINE = "[[mgr.keymap]]\non = \"Q\"\nrun = \"quit\"\n"
KEYMAP = "~/.config/yazi/keymap.toml"


def copy(sb):
    dst = sb.root + "/repo"
    shutil.copytree(REPO, dst, ignore=shutil.ignore_patterns(".git", "layers", "tests", "tasks"))
    sb.fake("yazi", "exit 0")                    # the component needs yazi on PATH
    return dst


def run(sb, repo, script, *args):
    p = subprocess.run([f"{repo}/{script}", "--yes", *args], env=sb.env, cwd=sb.home,
                       capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout + p.stderr


def test_no_file_makes_it(sb):
    repo = copy(sb)
    code, out = run(sb, repo, "install.sh", "yazi-keys")
    assert code == 0, out
    text = sb.read(KEYMAP) or ""
    assert START in text and "kill backward" in text, out


def test_existing_file_keeps_its_lines(sb):
    repo = copy(sb)
    sb.write(KEYMAP, MINE)
    run(sb, repo, "install.sh", "yazi-keys")
    text = sb.read(KEYMAP)
    assert text.startswith(MINE) and START in text


def test_again_changes_nothing(sb):
    repo = copy(sb)
    run(sb, repo, "install.sh", "yazi-keys")
    before = sb.read(KEYMAP)
    code, out = run(sb, repo, "install.sh", "yazi-keys")
    assert code == 0, out
    assert sb.read(KEYMAP) == before
    assert before.count(START) == 1


def test_uninstall_keeps_their_lines(sb):
    repo = copy(sb)
    sb.write(KEYMAP, MINE)
    run(sb, repo, "install.sh", "yazi-keys")
    code, out = run(sb, repo, "uninstall.sh", "yazi-keys")
    assert code == 0, out
    text = sb.read(KEYMAP)
    assert text is not None and START not in text and END not in text and "on = \"Q\"" in text, text


def test_uninstall_of_only_ours_deletes_the_file(sb):
    repo = copy(sb)
    run(sb, repo, "install.sh", "yazi-keys")
    run(sb, repo, "uninstall.sh", "yazi-keys")
    assert sb.read(KEYMAP) is None


def test_clash_with_prepend_list_skips(sb):
    repo = copy(sb)
    clash = "[mgr]\nprepend_keymap = [ { on = \"Q\", run = \"quit\" } ]\n"
    sb.write(KEYMAP, clash)
    code, out = run(sb, repo, "install.sh", "yazi-keys")
    assert sb.read(KEYMAP) == clash, "the file should be left alone"
    assert "prepend_keymap" in out, out
