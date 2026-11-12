"""hat's GitHub accounts list: alt-l signs gh in from the list, which stays open."""
import os

from term import Term
from worlds import HAT

GH = r'''
H="$HOME/.config/gh/hosts.yml"
hosts() { printf 'github.com:\n    users:\n'; for u in $1; do printf '        %s:\n' "$u"; done; printf '    user: %s\n' "$2"; }
users=$(sed -n 's/^        \(.*\):$/\1/p' "$H"); active=$(sed -n 's/^    user: //p' "$H")
case "$1 $2" in
  "auth login")
    echo "! First copy your one-time code: ABCD-1234" >&2; sleep 1
    b=$(cat "$HOME/browser"); hosts "$users $b" "$b" >"$H" ;;
  "auth switch") hosts "$users" "$6" >"$H" ;;
  "auth logout") hosts "$(echo "$users" | grep -vx "$6")" "$active" >"$H" ;;
esac
'''


def start(sb, browser):
    for a in ("me", "work"):
        sb.write(f"~/.config/hat/github/{a}.gitconfig", f"[user]\n\tname = {a}\n\temail = {a}@x.io\n")
    sb.write("~/.config/gh/hosts.yml", "github.com:\n    users:\n        work:\n    user: work\n")
    sb.write("~/browser", browser)
    sb.fake("gh", GH)
    sb.fake("xdg-open", "")
    sb.fake("wl-copy", "cat >/dev/null")
    proj = sb.path("~/code/proj")
    os.makedirs(proj)
    t = Term([HAT], sb.env, cwd=proj)
    t.wait_for("~/code/proj")
    t.settle()
    t.key("alt-g")
    t.wait_for("alt-l")
    t.settle()
    assert "not signed in" in (t.line_with("me@x.io") or ""), t.text()
    return t


def active(sb):
    return [l.split(": ")[1] for l in sb.read("~/.config/gh/hosts.yml").splitlines() if l.startswith("    user:")][0]


def test_alt_l_signs_gh_in_and_keeps_the_active_account(sb):
    t = start(sb, "me")
    t.key("alt-l")                                     # the cursor starts on "me"
    t.wait_for("ABCD-1234")
    assert t.alive(), "the list stays open while gh waits for the browser"
    t.wait_for("✓ gh is signed in as me")
    t.settle()
    assert "✓" in (t.line_with("me@x.io") or ""), "the GH column should update"
    assert active(sb) == "work", "gh's active account should be put back"
    assert any("login/device" in c for c in sb.calls("xdg-open")), sb.calls()
    t.key("esc", "esc")
    assert t.wait_exit() == 0


def test_browser_signed_in_as_someone_else_is_undone(sb):
    t = start(sb, "stranger")
    t.key("alt-l")
    t.wait_for("signed in as stranger")
    assert t.alive()
    hosts = sb.read("~/.config/gh/hosts.yml")
    assert "stranger" not in hosts and active(sb) == "work", hosts
    assert "not signed in" in (t.line_with("me@x.io") or "")
