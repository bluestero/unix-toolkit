"""A scratch world for one test: its own HOME, configs, and fake system commands.

Nothing a test runs can reach this machine's real settings, cloud or cluster:
HOME and XDG_* point into a temp folder, and every command that changes something
outside it (dconf, gsettings, gdbus, kubectl, aws, okta-aws-cli, xdg-open, sudo, apt,
...) is a fake on PATH that writes one line per call to calls.log.

    sb = Sandbox()
    sb.write("~/.okta/okta.yaml", "...")
    sb.calls("dconf")               # ["dconf reset -f /org/...", ...]
"""
import os
import shutil
import tempfile
import textwrap

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REAL_KUBECTL = shutil.which("kubectl") or ""

# Every fake logs its arguments; the body after that decides what it prints.
# $TK_FIX is the sandbox's fixture folder, where a test drops canned output.
FAKES = {
    # GNOME
    "gdbus": "exit 1",                                   # Window Calls missing
    "dconf": '[ "$1" = dump ] && echo "[/]"; exit 0',
    "gsettings": 'case "$*" in "get org.gnome.shell enabled-extensions") cat "$TK_FIX/enabled-extensions" 2>/dev/null || echo "@as []" ;; esac; exit 0',
    "gnome-extensions": "exit 1",
    "busctl": "exit 1",
    # cloud and login
    "okta-aws-cli": "exit 0",
    "aws": 'case "$*" in *"eks list-clusters"*) cat "$TK_FIX/clusters-$AWS_PROFILE" 2>/dev/null ;; esac; exit 0',
    "xdg-open": "exit 0",
    "open": "exit 0",
    "twingate": "exit 1",
    # system
    "sudo": "exit 1",
    "apt": "exit 1",
    "apt-get": "exit 1",
    "dpkg": "exit 1",
    "snap": "exit 1",
    "flatpak": "exit 1",
    "systemctl": "exit 1",
    "notify-send": "exit 0",
    "kitty": "exit 1",
    "ssh": "exit 255",
    "ssh-add": "exit 1",
    "pgrep": "exit 1",                                   # no IDE windows open
    "code": "exit 0",                                    # an IDE for ws
    # kubectl: `config` is the real one on the scratch kubeconfig; the rest is canned
    "kubectl": textwrap.dedent(r'''
        case "$1" in
          config) exec "$REAL_KUBECTL" "$@" ;;
          auth) echo yes; exit 0 ;;
          get)
            case "$*" in
              *ownerReferences*) echo ReplicaSet ;;
              *containerPort*|*".spec.ports"*) printf '8080\thttp\n' ;;
              *"-o jsonpath"*|*"-o go-template"*|*"-o yaml"*) ;;
              *) cat "$TK_FIX/kubectl-get-$2" 2>/dev/null || echo "No resources found" ;;
            esac; exit 0 ;;
          describe) echo "Name: $3"; exit 0 ;;
          *) exit 0 ;;                                   # delete, rollout, scale, ...: logged only
        esac'''),
}


class Sandbox:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="tk-test-")
        self.home = os.path.join(self.root, "home")
        self.bin = os.path.join(self.root, "bin")
        self.fix = os.path.join(self.root, "fix")
        self.log = os.path.join(self.root, "calls.log")
        for d in (self.home, self.bin, self.fix):
            os.makedirs(d)
        open(self.log, "w").close()
        for name, body in FAKES.items():
            self.fake(name, body)
        self.env = {
            "HOME": self.home,
            "USER": os.environ.get("USER", "test"),
            "LANG": "C.UTF-8",
            "TERM": "xterm-256color",
            "PATH": self.bin + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
            "XDG_CONFIG_HOME": self.home + "/.config",
            "XDG_DATA_HOME": self.home + "/.local/share",
            "XDG_STATE_HOME": self.home + "/.local/state",
            "XDG_CACHE_HOME": self.home + "/.cache",
            "XDG_RUNTIME_DIR": self.root + "/run",
            "TMPDIR": self.root + "/tmp",
            "GIT_CONFIG_NOSYSTEM": "1",
            "TK_CALLS": self.log,
            "TK_FIX": self.fix,
            "REAL_KUBECTL": REAL_KUBECTL,
        }
        os.makedirs(self.env["XDG_RUNTIME_DIR"], mode=0o700)
        os.makedirs(self.env["TMPDIR"])

    def path(self, p):
        return os.path.join(self.home, p[2:]) if p.startswith("~/") else p

    def fake(self, name, body):
        """A command on PATH that logs '<name> <args>' and then runs body (sh)."""
        f = os.path.join(self.bin, name)
        with open(f, "w") as fh:
            fh.write('#!/bin/sh\necho "%s $*" >>"$TK_CALLS"\n%s\n' % (name, body))
        os.chmod(f, 0o755)

    def write(self, p, text):
        p = self.path(p)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(textwrap.dedent(text).lstrip("\n"))
        return p

    def read(self, p):
        p = self.path(p)
        return open(p).read() if os.path.exists(p) else None

    def calls(self, name=None):
        lines = [l for l in open(self.log).read().splitlines() if l]
        return [l for l in lines if name is None or l.split(" ", 1)[0] == name]

    def add_path(self, d):
        """Put a folder (e.g. the repo's okta/bin) on PATH, after the fakes."""
        head, rest = self.env["PATH"].split(":", 1)
        self.env["PATH"] = f"{head}:{d}:{rest}"

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)
