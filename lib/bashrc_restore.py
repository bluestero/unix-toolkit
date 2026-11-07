"""Print ~/.bashrc with the lines the toolkit took out put back. uninstall.sh uses it.

    python3 -I lib/bashrc_restore.py <bashrc now> <original> <what the toolkit made of it>

The installer only ever takes lines out of ~/.bashrc (lib/bashrc_plan.py) and adds
its one init line. So undoing it is: find each run of lines that was taken out of
the original, and put it back right after the line it followed there (matched by
position, not by text, so a common line like "fi" can't mislead it). Anything you
changed since stays as you left it. A run whose neighbours are both gone goes at
the end, under a comment. Pass all three files without the init line.
"""
import difflib
import sys

now_path, orig_path, made_path = sys.argv[1:]
now = open(now_path).read().splitlines()
orig = open(orig_path).read().splitlines()
made = open(made_path).read().splitlines()


def same(a, b):
    """index in a -> index in b, for lines that are the same in both"""
    m = {}
    for blk in difflib.SequenceMatcher(None, a, b, autojunk=False).get_matching_blocks():
        m.update((blk.a + k, blk.b + k) for k in range(blk.size))
    return m


o2m, m2n = same(orig, made), same(made, now)
o2n = {i: m2n[j] for i, j in o2m.items() if j in m2n}  # original line -> where it is now

# Runs of original lines the toolkit dropped
runs = []
for i in range(len(orig)):
    if i in o2m:
        continue
    if runs and runs[-1][1] == i - 1:
        runs[-1][1] = i
    else:
        runs.append([i, i])

inserts, leftover = [], []
for n, (first, last) in enumerate(runs):
    lines = orig[first:last + 1]
    before = next((o2n[k] for k in range(first - 1, -1, -1) if k in o2n), None)
    after = next((o2n[k] for k in range(last + 1, len(orig)) if k in o2n), None)
    if before is not None:
        inserts.append((before + 1, n, lines))
    elif after is not None:
        inserts.append((after, n, lines))
    elif any(l.strip() for l in lines):
        leftover.extend(lines)

out = list(now)
# from the bottom up, so earlier positions stay valid; same spot keeps the original order
for at, _, lines in sorted(inserts, key=lambda t: (t[0], t[1]), reverse=True):
    out[at:at] = lines
if leftover:
    out += ["", "# Put back by the work toolkit's uninstall (from your ~/.bashrc before it)"] + leftover

text = "\n".join(out)
while "\n\n\n" in text:
    text = text.replace("\n\n\n", "\n\n")
sys.stdout.write(text.strip("\n") + "\n")
