"""kx: the context picker, kx sync's checklist and a resource list (kx pods), all on a
scratch kubeconfig and a fake kubectl / aws (tests/lib/fixture.py). Questions open in the list."""
from term import Term
from worlds import KX, current_context, kube


def start(sb):
    kube(sb)
    t = Term([KX], sb.env)
    t.wait_for("context>")
    t.wait_for("data-prod")
    return t


# ------------------------------------------------------------- the picker
def test_enter_on_expired_login_asks_then_no_switches(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Refresh now?")
    assert "data-prod" in t.text(), "the list should stay visible under the question"
    t.key("n")
    assert t.wait_exit() == 0
    assert sb.calls("okta-aws-cli") == []
    assert "shop-dev" in (sb.read("~/kx-shell.yaml") or ""), "this shell's overlay should point at shop-dev"


def test_enter_on_expired_login_then_yes_refreshes(sb):
    t = start(sb)
    t.key("enter")
    t.wait_for("Refresh now?")
    t.key("y")
    assert t.wait_exit() == 0
    assert any("--profile shop-dev" in c for c in sb.calls("okta-aws-cli")), sb.calls()


def test_prod_default_no_keeps_the_list_open(sb):
    t = start(sb)
    t.key("down", "ctrl-d")
    t.wait_for("PROD cluster")
    t.key("n")
    t.wait_gone("PROD cluster")
    t.wait_for("context>")
    assert t.alive(), "the list should stay open after the answer"
    assert current_context(sb) == "shop-dev"
    t.key("esc")
    t.wait_exit()


def test_prod_default_yes_sets_it_and_stays(sb):
    t = start(sb)
    t.key("down", "ctrl-d")
    t.wait_for("PROD cluster")
    t.key("y")
    t.wait_gone("PROD cluster")
    t.settle()
    assert t.alive(), "the list should stay open after the answer"
    t.key("esc")
    t.wait_exit()
    assert current_context(sb) == "data-prod"


# ------------------------------------------------------------- kx sync
# shop-dev-eks is added already, shop-new-eks is new
def sync(sb, clusters="shop-dev-eks shop-new-eks"):
    kube(sb)
    sb.write(sb.fix + "/clusters-shop-dev", clusters + "\n")
    sb.write(sb.fix + "/clusters-shop-prod", "")
    t = Term([KX, "sync"], sb.env)
    t.wait_for("which AWS accounts?")
    t.settle()
    t.key("enter")
    t.wait_for("which clusters?")
    t.wait_for(clusters.split()[-1])
    t.settle()
    return t


def test_sync_unticking_an_added_cluster_asks_then_no_keeps_it(sb):
    t = sync(sb)
    t.key("tab", "enter")                       # untick shop-dev (added), apply
    t.wait_for("(unticked)?")
    assert "shop-new-eks" in t.text(), "the checklist should stay visible under the question"
    t.key("n")
    t.wait_exit()
    assert "name: shop-dev" in sb.read("~/.kube/config")
    assert not any("update-kubeconfig --name shop-dev-eks" in c for c in sb.calls("aws"))


def test_sync_unticking_then_yes_removes_it(sb):
    t = sync(sb)
    t.key("tab", "enter")
    t.wait_for("(unticked)?")
    t.key("y")
    t.wait_exit()
    assert "name: shop-dev" not in sb.read("~/.kube/config")


def test_sync_unticking_the_only_cluster_still_asks(sb):
    t = sync(sb, "shop-dev-eks")
    t.key("ctrl-a", "enter")                    # all/none: nothing ticked, apply
    t.wait_for("(unticked)?")
    t.key("y")
    t.wait_exit()
    assert "name: shop-dev" not in sb.read("~/.kube/config")


def test_sync_unticking_every_account_searches_none(sb):
    kube(sb)
    t = Term([KX, "sync"], sb.env)
    t.wait_for("which AWS accounts?")
    t.settle()
    t.key("ctrl-a", "enter")
    t.wait_exit()
    assert "No accounts ticked" in t.flat()
    assert not any("list-clusters" in c for c in sb.calls("aws")), sb.calls("aws")


# ------------------------------------------------------------- kx pods
def pods(sb):
    kube(sb)
    sb.write(sb.fix + "/kubectl-get-pods", """
        NAME              READY   STATUS    RESTARTS   AGE
        web-7d4b9c-abcde  1/1     Running   0          5m
        web-7d4b9c-fghij  1/1     Running   0          5m
        """)
    t = Term([KX, "pods", "-n", "web"], sb.env)
    t.wait_for("web-7d4b9c-abcde")
    t.settle()
    return t


def test_pods_restart_asks_then_no_does_nothing(sb):
    t = pods(sb)
    t.key("ctrl-r")
    t.wait_for("A fresh pod replaces it")
    assert "web-7d4b9c-fghij" in t.text(), "the list should stay visible under the question"
    t.key("n")
    t.wait_gone("A fresh pod replaces it")
    t.settle()
    assert t.alive()
    assert not any(" delete " in c for c in sb.calls("kubectl"))
    t.key("esc")
    t.wait_exit()


def test_pods_restart_yes_deletes_the_pod(sb):
    t = pods(sb)
    t.key("ctrl-r")
    t.wait_for("A fresh pod replaces it")
    t.key("y")
    t.wait_for("is being replaced")
    assert t.alive(), "the list should stay open"
    t.pause(0.05)              # 50 ms on: fzf --track ignores keys while it reloads, which used to
    t.key("x", gap=0.5)        # take a whole kubectl call (> 0.15 s even with the fake one)
    assert "pods> x" in t.flat(), "the key pressed after the result was lost"
    t.key("bs")
    assert any(c.startswith("kubectl delete pod web-7d4b9c-abcde") for c in sb.calls("kubectl")), sb.calls("kubectl")
    t.key("esc")
    t.wait_exit()


def test_pods_forward_wrong_port_asks_again_with_the_reason(sb):
    t = pods(sb)
    t.key("ctrl-f")
    t.wait_for("port:")
    t.wait_for("Forward")
    t.key("ctrl-u", "abc", "enter")
    t.wait_for("isn't a port")
    assert "abc" in (t.line_with("port:") or ""), "the typed text should be kept to fix"
    t.key("esc")
    t.wait_gone("isn't a port")
    t.settle()
    assert t.alive(), "esc on the question goes back to the list"
    assert not any("port-forward" in c for c in sb.calls("kubectl"))
    t.key("esc")
    t.wait_exit()
