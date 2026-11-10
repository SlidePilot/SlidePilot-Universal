#!/usr/bin/env python3
"""Print the UDID of an available iPad simulator for CI.

Reads `xcrun simctl list devices available --json` from stdin.
Preference: the pinned device on the pinned iOS version, then any iPad
on the pinned version, then any iPad on the newest iOS version.
Prints nothing if no iPad is available.

Usage: pick_ipad_simulator.py "<device name>" "<iOS version, e.g. 26.5>"
"""

import json
import re
import sys


def runtime_version(runtime_id):
    # e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-5 -> (26, 5)
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime_id)
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("-"))


def pick(devices_json, name, os_version):
    wanted = tuple(int(part) for part in os_version.split("."))
    ipads = []
    for runtime_id, devices in devices_json.get("devices", {}).items():
        version = runtime_version(runtime_id)
        if version is None:
            continue
        for device in devices:
            if device.get("isAvailable", True) and device.get("name", "").startswith("iPad"):
                ipads.append((version, device))

    for check in (
        lambda v, d: v == wanted and d["name"] == name,
        lambda v, d: v == wanted,
    ):
        for version, device in ipads:
            if check(version, device):
                return device
    if ipads:
        return max(ipads, key=lambda item: item[0])[1]
    return None


def main():
    name, os_version = sys.argv[1], sys.argv[2]
    device = pick(json.load(sys.stdin), name, os_version)
    if device:
        print(device["udid"])
        print(f"Using {device['name']} ({device['udid']})", file=sys.stderr)


if __name__ == "__main__":
    main()
