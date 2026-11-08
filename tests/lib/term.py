"""A terminal for tests: runs a command in a pseudo-terminal, sends keys, reads the screen.

    t = Term(["okcli"], env, cols=120, rows=30)
    t.wait_for("profile>")          # until the text is on screen (fails after a timeout)
    t.key("down", "enter")          # named keys or plain text
    t.wait_for("Refresh now?")
    t.wait_exit()                   # the exit code

The screen is a pyte emulator, so what's checked is what a person would see
(the last frame, not every byte that went by). Terminal queries that pickers send
(cursor position, device attributes, background colour) are answered.
"""
import fcntl
import os
import re
import select
import signal
import struct
import termios
import time

import pyte

KEYS = {
    "enter": "\r", "esc": "\x1b", "tab": "\t", "bs": "\x7f", "space": " ",
    "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
    "pgup": "\x1b[5~", "pgdn": "\x1b[6~", "home": "\x1b[H", "end": "\x1b[F",
    "alt-bs": "\x1b\x7f", "alt-enter": "\x1b\r",
    "alt-left": "\x1b[1;3D", "alt-right": "\x1b[1;3C",
    "alt-shift-left": "\x1b[1;4D", "alt-shift-right": "\x1b[1;4C",
}
for _c in "abcdefghijklmnopqrstuvwxyz":
    KEYS["ctrl-" + _c] = chr(ord(_c) - 96)
    KEYS["alt-" + _c] = "\x1b" + _c

QUERIES = [
    (re.compile(rb"\x1b\[6n"), "cursor"),
    (re.compile(rb"\x1b\[0?c"), b"\x1b[?62;c"),
    (re.compile(rb"\x1b\]11;\?(\x07|\x1b\\)"), b"\x1b]11;rgb:0000/0000/0000\x1b\\"),
    (re.compile(rb"\x1b\]10;\?(\x07|\x1b\\)"), b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"),
]


class Screen(pyte.Screen):
    def report_device_status(self, mode, *args, **kwargs):
        # pyte 0.8.2 crashes on private queries like yazi's ESC[?996n; the replies we
        # give are in QUERIES
        if kwargs.get("private"):
            return
        super().report_device_status(mode)


class TermError(AssertionError):
    pass


class Term:
    last = None   # the most recent Term, so a failing test can show its screen

    def __init__(self, cmd, env, cols=120, rows=30, cwd=None):
        self.cols, self.rows = cols, rows
        self.screen = Screen(cols, rows)
        self.stream = pyte.ByteStream(self.screen)
        self.raw = b""
        self.code = None
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        pid = os.fork()
        if pid == 0:
            os.setsid()
            os.close(master)
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            for fd in (0, 1, 2):
                os.dup2(slave, fd)
            if slave > 2:
                os.close(slave)
            if cwd:
                os.chdir(cwd)
            try:
                os.execvpe(cmd[0], cmd, env)
            finally:
                os._exit(127)
        os.close(slave)
        self.pid, self.fd = pid, master
        Term.last = self

    # ------------------------------------------------------------- reading
    def _pump(self, timeout):
        """Read what's there (waiting up to timeout); False once the program is gone."""
        if self.fd is None:
            return False
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return True
        try:
            data = os.read(self.fd, 65536)
        except OSError:
            data = b""
        if not data:
            self._reap()
            return False
        self.raw += data
        self.stream.feed(data)
        for pat, reply in QUERIES:
            for _ in pat.finditer(data):
                if reply == "cursor":
                    reply = f"\x1b[{self.screen.cursor.y + 1};{self.screen.cursor.x + 1}R".encode()
                os.write(self.fd, reply)
        return True

    def _reap(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        if self.code is None:
            _, status = os.waitpid(self.pid, 0)
            self.code = os.waitstatus_to_exitcode(status)

    def text(self):
        """The screen as lines, right spaces trimmed."""
        return "\n".join(line.rstrip() for line in self.screen.display)

    def flat(self):
        """The screen as one line with runs of spaces squeezed (text wrapped by a
        picker's fold still matches)."""
        return re.sub(r"\s+", " ", self.text())

    def line_with(self, needle):
        for line in self.screen.display:
            if needle in line:
                return line.rstrip()
        return None

    def cursor_line(self):
        """The row fzf's pointer (▶) is on, inside ui_fzf's box, or None."""
        for line in self.screen.display:
            if re.match(r"^[│ ]*▶", line):
                return line.rstrip()
        return None

    # ------------------------------------------------------------- waiting
    def wait(self, cond, timeout=8.0, what="the screen to change"):
        """Pump until cond(self) is true; returns the seconds it took."""
        start = time.monotonic()
        while True:
            if cond(self):
                return time.monotonic() - start
            if time.monotonic() - start > timeout:
                raise TermError(f"timed out after {timeout:.0f} s waiting for {what}")
            if not self._pump(0.005) and not cond(self):
                raise TermError(f"the program exited (code {self.code}) while waiting for {what}")

    def wait_for(self, needle, timeout=8.0):
        """Until the text is on screen (spaces squeezed, so wrapped text matches too)."""
        n = re.sub(r"\s+", " ", needle)
        return self.wait(lambda t: n in t.flat(), timeout, repr(needle))

    def wait_gone(self, needle, timeout=8.0):
        n = re.sub(r"\s+", " ", needle)
        return self.wait(lambda t: n not in t.flat(), timeout, f"{needle!r} to go away")

    def settle(self, quiet=0.3, timeout=8.0):
        """Until nothing has been drawn for `quiet` seconds (callbacks and reloads done)."""
        start = time.monotonic()
        last = time.monotonic()
        while time.monotonic() - start < timeout:
            n = len(self.raw)
            if not self._pump(0.02):
                return
            if len(self.raw) != n:
                last = time.monotonic()
            elif time.monotonic() - last >= quiet:
                return
        raise TermError(f"the screen kept changing for {timeout:.0f} s")

    def wait_exit(self, timeout=8.0):
        """Until the program exits; returns its exit code. A background job it left
        (still holding the terminal) doesn't count."""
        start = time.monotonic()
        while self.code is None:
            if time.monotonic() - start > timeout:
                raise TermError(f"still running after {timeout:.0f} s")
            self._pump(0.05)
            if self.code is None:
                pid, status = os.waitpid(self.pid, os.WNOHANG)
                if pid:
                    self.code = os.waitstatus_to_exitcode(status)
        return self.code

    def alive(self):
        self._pump(0)
        if self.code is None:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.code = os.waitstatus_to_exitcode(status)
        return self.code is None

    # ------------------------------------------------------------- keys
    def key(self, *keys, gap=0.15):
        """Send each key (a name from KEYS, or text typed as is), letting the
        screen catch up for `gap` seconds after each."""
        for k in keys:
            os.write(self.fd, KEYS.get(k, k).encode())
            end = time.monotonic() + gap
            while time.monotonic() < end and self._pump(0.01):
                pass

    def pause(self, secs):
        """Let the program run (reading its output) for secs."""
        end = time.monotonic() + secs
        while time.monotonic() < end and self._pump(0.005):
            pass

    def timed_key(self, k, cond=None, timeout=5.0):
        """Send one key; the seconds until the screen changes (or cond holds)."""
        before = self.text()
        os.write(self.fd, KEYS.get(k, k).encode())
        return self.wait(cond or (lambda t: t.text() != before), timeout, f"a change after {k}")

    def resize(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.screen.resize(rows, cols)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.kill(self.pid, signal.SIGWINCH)

    def close(self):
        if self.fd is not None:
            try:
                os.killpg(self.pid, signal.SIGTERM)
            except OSError:
                pass
            deadline = time.monotonic() + 2
            while self.fd is not None and time.monotonic() < deadline:
                self._pump(0.05)
            if self.fd is not None:
                try:
                    os.killpg(self.pid, signal.SIGKILL)
                except OSError:
                    pass
                self._reap()
