"""okcli's picker: questions open in the list (CLAUDE.md, tasks/03)."""
from term import Term
from worlds import OKCLI, aws


def start(sb):
    aws(sb)
    t = Term([OKCLI], sb.env)
    t.wait_for("profile>")
    t.wait_for("shop-prod")
    return t


def test_enter_on_expired_asks_in_the_list_then_yes_refreshes(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Refresh now?")
    assert "shop-prod" in t.text(), "the list should stay visible under the question"
    t.key("y")
    assert t.wait_exit() == 0
    assert any("--profile shop-dev" in c for c in sb.calls("okta-aws-cli")), sb.calls()
    assert "export AWS_PROFILE=shop-dev" in (sb.read("~/okcli.eval") or "")


def test_enter_on_expired_then_no_switches_without_refresh(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Refresh now?")
    t.key("n")
    assert t.wait_exit() == 0
    assert sb.calls("okta-aws-cli") == []
    assert "export AWS_PROFILE=shop-dev" in (sb.read("~/okcli.eval") or "")


def test_esc_on_the_question_is_no(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Refresh now?")
    t.key("esc")
    assert t.wait_exit() == 0
    assert sb.calls("okta-aws-cli") == []
    assert "export AWS_PROFILE=shop-dev" in (sb.read("~/okcli.eval") or "")


def test_esc_on_the_list_does_nothing(sb):
    t = start(sb)
    t.key("esc")
    assert t.wait_exit() == 0
    assert not sb.read("~/okcli.eval")


def test_prod_default_no_keeps_it(sb):
    t = start(sb)
    t.key("down", "ctrl-d")
    t.wait_for("PROD profile")
    assert "shop-dev" in t.text(), "the list should stay visible under the question"
    t.key("n")
    t.wait_exit()
    assert sb.read("~/.config/okcli/default") is None


def test_prod_default_yes_sets_it(sb):
    t = start(sb)
    t.key("down", "ctrl-d")
    t.wait_for("PROD profile")
    t.key("y")
    t.wait_exit()
    assert (sb.read("~/.config/okcli/default") or "").strip() == "shop-prod"
