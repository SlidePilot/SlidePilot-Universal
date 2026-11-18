#!/usr/bin/env python3
"""Drives the SlidePilot test build through the SlidePilot Test Host (ADR 0018).

Run from the repository root with `python3 -I scripts/mac-test-host.py <command>`.
The host app must be running (menu bar icon). It captures and controls only the
test build; this script only writes requests into the exchange folder and copies
results into ./.pr-screenshots/mac/.

Commands:
  status
  launch [--appearance light|dark] [--fixture FILE ...] [--app PATH]
  open --fixture FILE [...]
  activate | quit | windows | tree
  screenshot NAME [--window ID]          -> .pr-screenshots/mac/NAME.png
  record-start NAME [--max-seconds N]    -> .pr-screenshots/mac/NAME.mov on record-stop
  record-stop
  menu TITLE [TITLE ...] [--open]        e.g. menu View "Enter Full Screen"
  press (--path 0.1.2 | --role R --title T --id I --label L)
  key COMBO                              e.g. key cmd+shift+right
  type TEXT
  click X Y [--window ID] [--right] [--count N]   (points from the window's top-left)
  drag X1 Y1 X2 Y2 [X Y ...] [--window ID]
  scroll X Y [--dx N] [--dy N] [--window ID]
"""

import argparse
import json
import os
import shutil
import sys
import time
import uuid

EXCHANGE = "/private/tmp/claude/slidepilot-testhost"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_APP = os.path.join(REPO, "build/TestHostApp/Build/Products/Debug/SlidePilot.app")
OUTPUT = os.path.join(REPO, ".pr-screenshots", "mac")


def folder(name):
    path = os.path.join(EXCHANGE, name)
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def request(command, args=None, timeout=60):
    request_id = "%016d-%s" % (time.time_ns() // 1000, uuid.uuid4().hex[:8])
    response_path = os.path.join(folder("responses"), request_id + ".json")
    temp = os.path.join(folder("requests"), request_id + ".tmp")
    with open(temp, "w") as file:
        json.dump({"id": request_id, "command": command, "args": args or {}}, file)
    os.rename(temp, temp[:-4] + ".json")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(response_path):
            time.sleep(0.05)
            with open(response_path) as file:
                response = json.load(file)
            os.remove(response_path)
            if not response.get("ok"):
                sys.exit("error: " + response.get("error", "unknown"))
            return response.get("result")
        time.sleep(0.1)
    sys.exit("error: no answer from the test host. Is \"SlidePilot Test Host\" running (menu bar)?")


def copy_fixtures(names):
    """Copies fixtures from Fixtures/ into the host's inbox. Only plain files of
    the repository's Fixtures folder are accepted."""
    inbox = folder("inbox")
    fixtures = os.path.realpath(os.path.join(REPO, "Fixtures"))
    copied = []
    for name in names:
        source = os.path.realpath(os.path.join(fixtures, name))
        if os.path.dirname(source) != fixtures or not os.path.isfile(source):
            sys.exit("error: %s is not a file in Fixtures/" % name)
        target = os.path.join(inbox, os.path.basename(source))
        if os.path.lexists(target):
            os.remove(target)
        shutil.copyfile(source, target)
        copied.append(os.path.basename(source))
    return copied


def fetch(name):
    os.makedirs(OUTPUT, exist_ok=True)
    source = os.path.join(EXCHANGE, "out", name)
    target = os.path.join(OUTPUT, name)
    shutil.move(source, target)
    return os.path.relpath(target, os.getcwd())


def window_args(namespace):
    return {"window": namespace.window} if namespace.window is not None else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for simple in ["status", "activate", "quit", "windows", "tree", "record-stop"]:
        sub.add_parser(simple)
    p = sub.add_parser("launch")
    p.add_argument("--app", default=DEFAULT_APP)
    p.add_argument("--appearance", choices=["light", "dark"])
    p.add_argument("--fixture", action="append", default=[])
    p = sub.add_parser("open")
    p.add_argument("--fixture", action="append", required=True)
    p = sub.add_parser("screenshot")
    p.add_argument("name")
    p.add_argument("--window", type=int)
    p = sub.add_parser("record-start")
    p.add_argument("name")
    p.add_argument("--max-seconds", type=int, default=60)
    p = sub.add_parser("menu")
    p.add_argument("titles", nargs="+")
    p.add_argument("--open", action="store_true")
    p = sub.add_parser("press")
    p.add_argument("--path")
    p.add_argument("--role")
    p.add_argument("--title")
    p.add_argument("--id")
    p.add_argument("--label")
    p = sub.add_parser("key")
    p.add_argument("combo")
    p = sub.add_parser("type")
    p.add_argument("text")
    p = sub.add_parser("click")
    p.add_argument("x", type=float)
    p.add_argument("y", type=float)
    p.add_argument("--window", type=int)
    p.add_argument("--right", action="store_true")
    p.add_argument("--count", type=int, default=1)
    p = sub.add_parser("drag")
    p.add_argument("coords", type=float, nargs="+")
    p.add_argument("--window", type=int)
    p = sub.add_parser("scroll")
    p.add_argument("x", type=float)
    p.add_argument("y", type=float)
    p.add_argument("--dx", type=int, default=0)
    p.add_argument("--dy", type=int, default=0)
    p.add_argument("--window", type=int)
    a = parser.parse_args()

    c = a.command
    if c == "launch":
        args = {"app": os.path.realpath(a.app), "documents": copy_fixtures(a.fixture)}
        if a.appearance:
            args["appearance"] = a.appearance
        result = request(c, args)
    elif c == "open":
        result = request(c, {"documents": copy_fixtures(a.fixture)})
    elif c == "screenshot":
        info = request(c, {"name": a.name + ".png", **window_args(a)})
        result = "%s (%dx%d)" % (fetch(info["file"]), info["width"], info["height"])
    elif c == "record-start":
        result = request(c, {"name": a.name + ".mov", "maxSeconds": a.max_seconds})
    elif c == "record-stop":
        result = fetch(request(c)["file"])
    elif c == "menu":
        result = request(c, {"path": a.titles, "open": a.open})
    elif c == "press":
        match = {k: v for k, v in {"role": a.role, "title": a.title, "id": a.id, "label": a.label}.items() if v}
        result = request(c, {"path": a.path} if a.path else {"match": match})
    elif c == "key":
        result = request(c, {"keys": a.combo})
    elif c == "type":
        result = request(c, {"text": a.text})
    elif c == "click":
        result = request(c, {"at": [a.x, a.y], "button": "right" if a.right else "left", "count": a.count, **window_args(a)})
    elif c == "drag":
        if len(a.coords) < 4 or len(a.coords) % 2:
            sys.exit("error: drag needs pairs of coordinates (at least two points)")
        points = [[a.coords[i], a.coords[i + 1]] for i in range(0, len(a.coords), 2)]
        result = request(c, {"points": points, **window_args(a)})
    elif c == "scroll":
        result = request(c, {"at": [a.x, a.y], "dx": a.dx, "dy": a.dy, **window_args(a)})
    else:
        result = request(c)

    print(result if isinstance(result, str) else json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
