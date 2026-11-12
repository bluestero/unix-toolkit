"""airpost: the secrets list (values never shown), and sync of your secret files with the repo."""
import os
import stat
import subprocess

from fixture import REPO
from term import Term

AP = os.path.join(REPO, "layers/airpr/bin/airpost")
COLS = "~/Desktop/Work/AirPR/airpr-postman-collections"


def repo(sb):
    """A small collections repo: DEV has two secrets, one a token a script sets."""
    sb.write(f"{COLS}/postman/environments/DEV.environment.yaml",
             "name: DEV\nvalues:\n  - key: API_URL\n    value: https://x\n  - key: API_KEY\n    secret: true\n"
             "  - key: NEW_KEY\n    secret: true\n  - key: GOLD_TOKEN\n    secret: true\ncolor: 120\n")
    sb.write(f"{COLS}/postman/environments/PROD.environment.yaml", "name: PROD\nvalues:\n  - key: API_KEY\n    secret: true\n")
    sb.write(f"{COLS}/postman/collections/Shop/Get.request.yaml",
             "url: '{{API_URL}}/x?k={{API_KEY}}'\nscripts: pm.environment.set(`${tier}_TOKEN`, 1)\n")


def run(sb, *args):
    return subprocess.run([AP, *args], env=sb.env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)


def secrets_file(sb):
    return sb.path("~/.config/airpr-postman/DEV.env")


def test_sync_lists_adds_and_removes_but_not_tokens(sb):
    repo(sb)
    sb.write("~/.config/airpr-postman/DEV.env", "API_KEY=k\nOLD_ONE=v\n")
    out = run(sb, "sync").stdout
    assert "ADD" in out and "NEW_KEY" in out, out
    assert "REMOVE" in out and "OLD_ONE" in out and "its value goes too" in out, out
    assert "GOLD_TOKEN" not in out, "a token a script sets is not a secret to fill in"


def test_sync_picker_applies_only_the_ticked(sb):
    repo(sb)
    sb.write("~/.config/airpr-postman/DEV.env", "# mine\nAPI_KEY=k\nOLD_ONE=v\n")
    sb.write("~/.config/airpr-postman/PROD.env", "API_KEY=p\n")
    t = Term([AP, "sync"], sb.env)
    t.wait_for("NEW_KEY")
    t.settle()
    t.key("tab", "tab")          # ticks ADD NEW_KEY, then REMOVE OLD_ONE
    t.key("enter")
    assert t.wait_exit() == 0
    text = open(secrets_file(sb)).read()
    assert text == "# mine\nAPI_KEY=k\nNEW_KEY=\n", text


def test_secrets_list_sets_a_value_without_showing_it(sb):
    repo(sb)
    t = Term([AP], sb.env)                           # the bare command opens the list
    t.wait_for("PROD")
    t.settle()
    assert "0 of 2" in (t.line_with("DEV") or "") and "not made yet" in (t.line_with("DEV") or ""), t.text()
    t.key("enter")                                   # DEV is first
    t.wait_for("API_KEY")
    t.settle()
    assert "– empty" in (t.line_with("API_KEY") or "") and "Shop" in (t.line_with("API_KEY") or ""), t.text()
    t.key("enter")                                   # set API_KEY: asked in the list
    t.wait_for("New value for API_KEY in DEV?")
    assert "PROD" not in t.text() and "API_KEY" in (t.line_with("– empty") or ""), "the list stays"
    t.key("enter")                                   # nothing typed: asked again, nothing saved
    t.wait_for("Type the value")
    t.key("   ", "enter")                            # spaces alone are nothing too
    t.settle()
    assert "Type the value" in t.text() and "✓ API_KEY set" not in t.text(), t.text()
    assert not os.path.exists(secrets_file(sb)), "nothing was saved"
    t.key("ctrl-u", "s3cret-v4lue", "enter")
    t.wait_for("✓ API_KEY set")
    t.settle()
    assert "s3cret" not in t.text(), "the value leaves the prompt once saved"
    assert "✓ set" in (t.line_with("API_KEY") or ""), t.text()
    f = secrets_file(sb)
    assert "API_KEY=s3cret-v4lue\n" in open(f).read()
    assert stat.S_IMODE(os.stat(f).st_mode) == 0o600
    t.key("esc")                                     # back to the environments
    t.wait_for("1 of 2")
    assert "~/.config/airpr-postman/DEV.env" in (t.line_with("DEV") or ""), t.text()
    t.key("esc")
    assert t.wait_exit() == 0


def test_add_asks_in_the_header_and_a_bad_name_asks_again(sb):
    repo(sb)
    t = Term([AP, "secrets", "dev"], sb.env)
    t.wait_for("API_KEY")
    t.settle()
    t.key("alt-a")
    t.wait_for("Name of the new DEV secret")
    t.key("lower")
    t.key("enter")
    t.wait_for("Use capitals")
    assert t.alive()
    t.key("ctrl-u")
    t.key("EXTRA_ONE", "enter")
    t.wait_for("New value for EXTRA_ONE in DEV?")
    t.key("v", "enter")
    t.wait_for("✓ EXTRA_ONE set")
    t.settle()
    assert "only in your file" in (t.line_with("EXTRA_ONE") or ""), t.text()
    t.key("up")                                      # EXTRA_ONE is the last row (the list wraps)
    t.key("ctrl-x")                                  # only in your file: removed, asks first, default no
    t.wait_for("Remove EXTRA_ONE from your DEV file?")
    t.key("y")
    t.wait_for("✓ EXTRA_ONE removed")
    assert "EXTRA_ONE" not in open(secrets_file(sb)).read()
    t.settle()
    assert t.line_with("only in your file") is None, t.text()
    t.key("esc", "esc")
    assert t.wait_exit() == 0


def test_ls_lists_collections_and_environments(sb):
    repo(sb)
    out = run(sb, "ls").stdout
    assert "COLLECTION" in out and "REQUESTS" in out and "Shop" in out, out
    assert "ENV" in out and "not made yet" in out, out


def test_sync_picker_lays_out_its_columns(sb):
    repo(sb)
    sb.write("~/.config/airpr-postman/DEV.env", "API_KEY=k\n")
    t = Term([AP, "sync"], sb.env)
    t.wait_for("NEW_KEY")
    t.settle()
    row = t.line_with("NEW_KEY") or ""
    assert "ADD" in row and "DEV   " in row and "NEW_KEY   " in row, t.text()
    t.key("esc")
    t.wait_exit()
