"""Installer parts' own checks, in a scratch copy of the repo (feelkit included) with a scratch
HOME: Claude parts in every profile, the PROD guard without tk, looks (a missing preset, files
copied out of the repo), kitty accents without a background.conf, tk layer rm's advice."""
import os
import shutil
import subprocess

from fixture import REPO

PROFILES = ["~/.claude", "~/.claude-profiles/work", "~/.claude-profiles/home"]


def copy(sb):
    dst = sb.root + "/repo"
    shutil.copytree(REPO, dst, ignore=shutil.ignore_patterns(".git", "tests", "tasks", "airpr", "*.zip"))
    return dst


def no_host_tk(sb):
    """PATH without any folder of the machine's that has a tk (~/.local/bin, the toolkit's bin)."""
    sb.env["PATH"] = ":".join(p for p in sb.env["PATH"].split(":") if not os.access(os.path.join(p, "tk"), os.X_OK))


def sh(sb, repo, script):
    """Runs bash with the installer's libraries loaded; returns its output."""
    pre = f'repo={repo} mode=yes details=0; . "$repo/lib/setup.sh"; . "$repo/lib/components.sh"\n'
    p = subprocess.run(["bash", "-c", pre + script], env=sb.env, cwd=sb.home, capture_output=True, text=True,
                       timeout=60, stdin=subprocess.DEVNULL)
    return p.stdout + p.stderr


def install(sb, repo, *parts):
    p = subprocess.run([repo + "/install.sh", "--yes", *parts], env=sb.env, cwd=sb.home, capture_output=True,
                       text=True, timeout=60, stdin=subprocess.DEVNULL)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout


def profiles(sb):
    for d in PROFILES:
        os.makedirs(sb.path(d), exist_ok=True)
    sb.env.pop("CLAUDE_CONFIG_DIR", None)


def test_claude_parts_go_in_every_profile(sb):
    repo = copy(sb)
    profiles(sb)
    install(sb, repo, "commands", "claude-skill", "claude-hook", "claude-guard")
    for d in PROFILES:
        text = sb.read(d + "/settings.json") or ""
        assert "ctx plain" in text and "tk __guard" in text, (d, text)
        assert os.path.islink(sb.path(d + "/skills/work-toolkit")), d
    out = sh(sb, repo, "for id in claude-skill claude-hook claude-guard; do component_state $id; echo $id $STATE; done")
    assert out.split() == ["claude-skill", "installed", "claude-hook", "installed", "claude-guard", "installed"], out


def test_a_profile_without_the_hook_is_partial(sb):
    repo = copy(sb)
    profiles(sb)
    install(sb, repo, "claude-hook")
    os.remove(sb.path("~/.claude-profiles/home/settings.json"))
    out = sh(sb, repo, 'component_state claude-hook; echo "$STATE|$NOTE"')
    assert out.strip() == "partial|not in ~/.claude-profiles/home", out


def test_guard_without_tk_needs_a_fix(sb):
    repo = copy(sb)
    profiles(sb)
    no_host_tk(sb)
    install(sb, repo, "claude-guard")                    # the hook is in, but no tk to run it
    out = sh(sb, repo, 'component_state claude-guard; echo "$STATE|$NOTE"')
    assert out.startswith("partial|it can't run: the tk command isn't on PATH"), out
    install(sb, repo, "commands")                        # ~/.local/bin/tk
    out = sh(sb, repo, 'PATH=$HOME/.local/bin:$PATH; component_state claude-guard; echo "$STATE"')
    assert out.strip() == "installed", out


def test_a_missing_look_is_never_applied(sb):
    repo = copy(sb)
    out = sh(sb, repo, 'look_applied /org/x/ /no/such/settings.dconf && echo applied || echo not;'
                       ' look_apply /org/x/ /no/such/settings.dconf x || echo failed')
    assert "not" in out and "failed" in out and "missing" in out, out
    assert not any("load" in c for c in sb.calls("dconf")), sb.calls("dconf")


def test_a_look_file_is_copied_out_of_the_repo(sb):
    repo = copy(sb)
    look = repo + "/layers/feelkit/gnome/dash-to-panel/settings.dconf"
    out = sh(sb, repo, f'look_apply /org/x/ {look} dash-to-panel && look_file {look} | grep show-apps-icon-file')
    copied = sb.path("~/.local/share/work-toolkit/looks/dash-to-panel/apps-button.svg")
    assert os.path.isfile(copied), out
    assert copied in out and repo not in out, out
    shutil.rmtree(repo + "/layers/feelkit/gnome/dash-to-panel")   # the layer's files gone: the icon stays
    assert os.path.isfile(copied)


def test_kitty_accents_need_a_background_conf(sb):
    repo = copy(sb)
    sb.fake("kitty", "exit 0")
    install(sb, repo, "kitty-config")
    out = sh(sb, repo, 'component_state kitty-accents; echo "$STATE"; uninstall_kitty_accents')
    assert out.splitlines()[0] == "missing", out          # k-bg reads a missing file as accents on
    assert not os.path.exists(sb.path("~/.config/kitty/background.conf")), "the uninstall must not make one"


def test_layer_rm_names_the_layers_own_uninstall(sb):
    repo = copy(sb)
    p = subprocess.run([repo + "/bin/tk", "layer", "rm", "feelkit"], env=sb.env, cwd=sb.home, capture_output=True,
                       text=True, timeout=60, stdin=subprocess.DEVNULL)
    assert "fk uninstall" in p.stdout + p.stderr, p.stdout + p.stderr
    assert os.path.isdir(repo + "/layers/feelkit"), "no terminal to confirm in: nothing removed"
