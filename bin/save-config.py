#!/usr/bin/env python3
"""Seed / write the Auggment Scoreboard config.

  save-config.py --ensure     create the config with defaults if it is missing
  save-config.py              read a JSON object from stdin and write it atomically

Standard library only. The config lives at ~/.config/auggment/scoreboard.json.
"""

import json
import os
import sys
import tempfile

CONFIG_DIR = os.path.expanduser("~/.config/auggment")
CONFIG_PATH = os.path.join(CONFIG_DIR, "scoreboard.json")

DEFAULTS = {
    "timezone": "America/Chicago",
    "leagues": ["football/nfl"],
    "teams": [],
    "racing": {},
    "golf": [],
    "team_colors": {},
    "days_back": 1,
    "days_ahead": 7,
    "refresh_seconds": 60,
    "rotate_seconds": 6,
    "max_games": 40,
}


def write_config(data):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CONFIG_DIR, prefix=".scoreboard.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, CONFIG_PATH)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    if "--ensure" in sys.argv[1:]:
        if not os.path.exists(CONFIG_PATH):
            write_config(DEFAULTS)
        return
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else dict(DEFAULTS)
    except Exception as exc:
        print(f"invalid json: {exc}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict):
        print("config must be a JSON object", file=sys.stderr)
        sys.exit(1)
    write_config(data)


if __name__ == "__main__":
    main()
