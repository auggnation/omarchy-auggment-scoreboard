#!/usr/bin/env python3
"""Seed / write the Auggment Scoreboard config.

  save-config.py --ensure     create the config with defaults if it is missing
  save-config.py --data JSON  write the given JSON object atomically (used by the widget)
  save-config.py              read a JSON object from stdin and write it atomically

The file is written with mode 0600 inside a 0700 directory. If an existing
config is unreadable (corrupt JSON) it is copied to scoreboard.json.corrupt
before being replaced, so a bad write never silently destroys favourites.

Standard library only. The config lives at ~/.config/auggment/scoreboard.json.
"""

import json
import os
import shutil
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
    "days_ahead_teams": {},
    "days_back": 1,
    "days_ahead": 7,
    "state_colors": {},
    "bar_logos": True,
    "league_in_cycle": False,
    "refresh_seconds": 60,
    "rotate_seconds": 6,
    "max_games": 40,
    "position": "right",
    "positioned": False,
}


def backup_if_corrupt():
    if not os.path.exists(CONFIG_PATH):
        return
    try:
        with open(CONFIG_PATH, "r") as fh:
            json.load(fh)
    except Exception:
        try:
            shutil.copy2(CONFIG_PATH, CONFIG_PATH + ".corrupt")
        except OSError:
            pass


def write_config(data):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    backup_if_corrupt()
    fd, tmp = tempfile.mkstemp(dir=CONFIG_DIR, prefix=".scoreboard.", suffix=".tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, CONFIG_PATH)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    if "--ensure" in sys.argv[1:]:
        if not os.path.exists(CONFIG_PATH):
            write_config(DEFAULTS)
        return
    args = sys.argv[1:]
    if "--data" in args and args.index("--data") + 1 < len(args):
        raw = args[args.index("--data") + 1]
    else:
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
