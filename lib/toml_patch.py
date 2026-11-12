"""toml_patch.py BASE PATCH OUT: BASE with PATCH laid over it (tables merged, PATCH's
values win), written to OUT. For configs that can't include another file (starship).
A PATCH that isn't valid TOML: OUT is left as it was, the error on stderr, exit 1."""
import json
import os
import re
import sys
import tomllib


def merge(base, patch):
    for k, v in patch.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v
    return base


def key(k):
    return k if re.fullmatch(r"[A-Za-z0-9_-]+", k) else json.dumps(k, ensure_ascii=False)


def value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)   # JSON's escapes are TOML's too
    if isinstance(v, list):
        return "[" + ", ".join(value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{key(k)} = {value(x)}" for k, x in v.items()) + " }"
    return json.dumps(str(v))


def dump(d, name=""):
    out, tables = [], []
    for k, v in d.items():
        (tables if isinstance(v, dict) else out).append((k, v))
    lines = [f"{key(k)} = {value(v)}" for k, v in out]
    if name and (lines or not tables):
        lines.insert(0, f"\n[{name}]")
    for k, v in tables:
        lines += dump(v, f"{name}.{key(k)}" if name else key(k))
    return lines


def main(base, patch, out):
    with open(base, "rb") as f:
        b = tomllib.load(f)
    try:
        with open(patch, "rb") as f:
            p = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        print(f"{patch}: {e}", file=sys.stderr)
        return 1
    text = f"# Made from {base} and your patch {patch}. Edit the patch, not this.\n"
    text += "\n".join(dump(merge(b, p))).lstrip("\n") + "\n"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out + ".tmp", "w") as f:
        f.write(text)
    os.replace(out + ".tmp", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
