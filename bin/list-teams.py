#!/usr/bin/env python3
"""List the teams in an ESPN league, for the Auggment Scoreboard settings picker.

Usage: list-teams.py <league/path>
Prints JSON: [{"abbr": "KC", "name": "Kansas City Chiefs", "logo": "...", "color": "#E31837"}]
Standard library only.
"""

import json
import os
import sys
from urllib import request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leagues  # noqa: E402  (shared source metadata; see bin/leagues.py)

# Slugs where the league path segment differs from ESPN's sport/league slugs.
SLUG_OVERRIDES = {
    "softball/college-softball": ("baseball", "college-softball"),
}
WEB_API_LEAGUES = {"softball/college-softball", "baseball/college-baseball"}


def http_json(url, timeout=8):
    req = request.Request(url, headers={
        "User-Agent": "AuggmentScoreboard/1.0",
        "Accept": "application/json",
    })
    with request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def main():
    if len(sys.argv) < 2:
        print(json.dumps([]))
        return
    path = sys.argv[1]
    if leagues.source_for(path) == "tsdb":
        out = [{"abbr": t["abbr"], "name": t["name"], "logo": "", "color": ""}
               for t in leagues.TSDB_TEAMS.get(path, [])]
        out.sort(key=lambda x: x["name"].lower())
        print(json.dumps(out))
        return
    sport, league = SLUG_OVERRIDES.get(path, (path.split("/")[0], path.split("/")[-1]))
    host = "site.web.api.espn.com" if path in WEB_API_LEAGUES else "site.api.espn.com"
    url = f"https://{host}/apis/site/v2/sports/{sport}/{league}/teams?limit=500"
    try:
        res = http_json(url)
        teams = res["sports"][0]["leagues"][0]["teams"]
    except Exception:
        print(json.dumps([]))
        return

    out = []
    for t in teams:
        team = t.get("team", {})
        abbr = team.get("abbreviation")
        name = team.get("displayName")
        if not abbr or not name:
            continue
        logos = team.get("logos") or []
        logo = logos[0].get("href", "") if logos and isinstance(logos[0], dict) else ""
        color = team.get("color", "")
        out.append({
            "abbr": abbr,
            "name": name,
            "logo": logo,
            "color": f"#{color}" if color else "",
        })
    out.sort(key=lambda x: x["name"].lower())
    print(json.dumps(out))


if __name__ == "__main__":
    main()
