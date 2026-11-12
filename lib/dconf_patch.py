"""dconf_patch.py: a look (a dconf dump of an extension's settings) and your patch on top.
  applied IGNORE LIVE PRESET [PATCH]  exit 0 when every setting of PRESET, with PATCH laid
                                      over it, is the same in LIVE (keys matching IGNORE skipped)
  diff IGNORE LIVE PRESET             what LIVE sets differently from PRESET, as a dconf dump:
                                      the patch that keeps those changes
"""
import re
import sys


def parse(p):
    d, sec = {}, ""
    try:
        lines = open(p).read().splitlines()
    except OSError:
        return d
    for line in lines:
        if line.startswith("["):
            sec = line
        elif "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            d[(sec, k)] = v
    return d


def main(cmd, ign, live, preset, patch=""):
    ign = re.compile(ign or r"(?!)")
    live, want = parse(live), parse(preset)
    if cmd == "applied":
        want.update(parse(patch) if patch else {})
        return 0 if all(live.get(k) == v for k, v in want.items() if not ign.match(k[1])) else 1
    out, sec = [], None
    for (s, k), v in live.items():
        if ign.match(k) or want.get((s, k)) == v:
            continue
        if s != sec:
            out.append(("\n" if out else "") + s)
            sec = s
        out.append(f"{k}={v}")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
