#!/usr/bin/env python3
"""Offline editor for the QNAP TS-41x U-Boot environment ("U-Boot Config", mtd4).

Works on a raw dump of the partition, so it runs on a PC; QTS needs no extra tools.

  Read on QTS:   ssh admin@NAS 'cat /dev/mtdblock4' > mtd4.bin
  Show:          qnap-uboot-env.py show mtd4.bin
  Edit:          qnap-uboot-env.py set mtd4.bin -o mtd4.new -s changes.txt
  Write on QTS:  ssh admin@NAS 'cat > /dev/mtdblock4' < mtd4.new   (only after review!)

Layout (as used by qnap_mtd_resize's fw_env.config): offset 0, env size 0x1000,
no redundant copy. The block starts with a little-endian CRC32 over the next
(env_size - 4) bytes; variables are NUL-terminated "name=value" strings, ended by
an empty string. The size is detected by checking which candidate gives a valid CRC.
Bytes after the env area (rest of the 256 KiB erase block) are kept as they are.

The changes file uses the script format of libubootenv's fw_setenv -s (the
fw_setenv in Debian 13): "name=value" sets a variable, "name" or "name=" deletes
it, "#" starts a comment. The same file therefore works on the PC (this tool)
and later on Debian (fw_setenv -s).
"""
import argparse
import sys
import zlib

CANDIDATE_SIZES = (0x1000, 0x2000, 0x4000, 0x8000, 0x10000, 0x20000, 0x40000)


def detect(blob, forced=None):
    sizes = (forced,) if forced else CANDIDATE_SIZES
    for size in sizes:
        if size > len(blob):
            continue
        stored = int.from_bytes(blob[0:4], "little")
        if zlib.crc32(blob[4:size]) & 0xFFFFFFFF == stored:
            return size
    return None


def parse(blob, size):
    data = blob[4:size]
    env, order = {}, []
    for raw in data.split(b"\0"):
        if not raw:
            break  # double NUL = end of environment
        name, sep, value = raw.partition(b"=")
        if not sep:
            raise ValueError(f"malformed entry without '=': {raw[:40]!r}")
        key = name.decode("latin-1")
        if key not in env:
            order.append(key)
        env[key] = value.decode("latin-1")
    return env, order


def build(blob, size, env, order):
    body = b"".join(f"{k}={env[k]}".encode("latin-1") + b"\0" for k in order if k in env) + b"\0"
    if len(body) > size - 4:
        raise ValueError(f"environment too large: {len(body)} > {size - 4} bytes")
    body = body + b"\0" * (size - 4 - len(body))
    crc = zlib.crc32(body) & 0xFFFFFFFF
    return crc.to_bytes(4, "little") + body + blob[size:]


def read_changes(path):
    changes = []
    with open(path, encoding="latin-1") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            name, sep, value = line.partition("=")
            if not name.replace("_", "").isalnum():
                raise ValueError(f"{path}:{n}: invalid variable name {name!r}")
            # "name=value" sets, "name" or "name=" deletes (same as libubootenv's fw_setenv -s)
            changes.append((name, value if sep and value else None))
    return changes


def load(path, forced):
    blob = open(path, "rb").read()
    size = detect(blob, forced)
    if size is None:
        sys.exit(f"{path}: no valid U-Boot env CRC found (tried {', '.join(hex(s) for s in CANDIDATE_SIZES)}). "
                 "Wrong partition, or U-Boot is running on its built-in defaults.")
    env, order = parse(blob, size)
    return blob, size, env, order


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--size", type=lambda s: int(s, 0), help="force env size instead of auto-detect")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show", help="print all variables")
    s.add_argument("dump")
    g = sub.add_parser("get", help="print one variable")
    g.add_argument("dump")
    g.add_argument("name")
    e = sub.add_parser("set", help="apply a fw_setenv-style script, write a new dump")
    e.add_argument("dump")
    e.add_argument("-s", "--script", required=True)
    e.add_argument("-o", "--output", required=True)
    a = ap.parse_args()

    blob, size, env, order = load(a.dump, a.size)
    if a.cmd == "show":
        print(f"# env size 0x{size:x}, {len(order)} variables, CRC ok", file=sys.stderr)
        for k in order:
            print(f"{k}={env[k]}")
    elif a.cmd == "get":
        if a.name not in env:
            sys.exit(f"{a.name}: not set")
        print(env[a.name])
    elif a.cmd == "set":
        for name, value in read_changes(a.script):
            if value is None:
                env.pop(name, None)
                print(f"- {name}", file=sys.stderr)
            else:
                if name not in env:
                    order.append(name)
                print(f"{'~' if name in env and env[name] != value else '+' if name not in env else '='} {name}={value}",
                      file=sys.stderr)
                env[name] = value
        new = build(blob, size, env, order)
        # self-check: the new dump must parse back to exactly this environment
        nsize = detect(new, size)
        nenv, _ = parse(new, nsize)
        assert nsize == size and nenv == {k: env[k] for k in order if k in env}, "round-trip check failed"
        with open(a.output, "wb") as fh:
            fh.write(new)
        print(f"wrote {a.output} ({len(new)} bytes, env size 0x{size:x})", file=sys.stderr)


if __name__ == "__main__":
    main()
