"""tk __guard, Claude Code's PreToolUse hook: asks only for PROD changes and inherited PROD targets."""
import json
import os
import subprocess

from fixture import REPO
from worlds import kube

GUARD = os.path.join(REPO, "claude/guard.sh")


def guard(sb, command, **env):
    out = subprocess.run([GUARD], input=json.dumps({"cwd": sb.path("~"), "tool_input": {"command": command}}),
                         env={**sb.env, **env}, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)["hookSpecificOutput"] if out.stdout.strip() else {}


def asks(sb, command, **env):
    return guard(sb, command, **env).get("permissionDecision") == "ask"


def test_prod_changes_ask_reads_and_dev_dont(sb):
    kube(sb)
    for c in ["okcli exec shop-prod -- aws s3 rm s3://b/k",
              "aws --profile shop-prod ec2 terminate-instances --instance-ids i-1",
              "AWS_PROFILE=shop-prod aws s3 cp a s3://b",
              "kx exec data-prod -- kubectl delete pod p",
              "kubectl --context data-prod rollout restart deploy/x"]:
        assert asks(sb, c), c
    for c in ["git status", "ls | grep aws",
              "okcli exec shop-prod -- aws s3 ls",
              "kx exec data-prod -- kubectl get pods && rm -rf build",
              "okcli exec shop-dev -- aws s3 rm s3://b/k",
              "kubectl --context shop-dev delete pod p",
              "kubectl get pods"]:
        assert not asks(sb, c), c


def test_bare_aws_asks_only_when_the_inherited_profile_is_prod(sb):
    kube(sb)
    assert asks(sb, "aws s3 ls", AWS_PROFILE="shop-prod")
    assert not asks(sb, "aws s3 ls", AWS_PROFILE="shop-dev")


def test_expired_session_is_a_note_not_a_question(sb):
    kube(sb)
    out = guard(sb, "okcli exec shop-dev -- aws s3 ls")
    assert "permissionDecision" not in out
    assert "okcli refresh shop-dev" in out["additionalContext"]
