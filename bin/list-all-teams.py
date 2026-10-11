#!/usr/bin/env python3
"""List every team across the given leagues, as MultiSelect options for the
Auggment Scoreboard settings panel.

Usage: list-all-teams.py <league/path> [<league/path> ...]
Prints JSON: [{"value": "football/nfl:KC", "label": "Kansas City Chiefs (NFL)",
              "description": "NFL"}]  sorted by label. Standard library only.
"""

import json
import os
import sys
from urllib import request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leagues  # noqa: E402  (shared source metadata; see bin/leagues.py)

SLUG_OVERRIDES = {
    "softball/college-softball": ("baseball", "college-softball"),
}
WEB_API_LEAGUES = {"softball/college-softball", "baseball/college-baseball"}

LABELS = {
    "football/nfl": "NFL", "football/cfl": "CFL", "football/xfl": "XFL",
    "football/college-football": "NCAA Football",
    "baseball/mlb": "MLB", "baseball/college-baseball": "NCAA Baseball", "baseball/milb": "MiLB",
    "basketball/nba": "NBA", "basketball/wnba": "WNBA", "basketball/euroleague": "EuroLeague",
    "basketball/mens-college-basketball": "NCAA Men's Basketball",
    "basketball/womens-college-basketball": "NCAA Women's Basketball",
    "hockey/nhl": "NHL", "hockey/mens-college-hockey": "NCAA Hockey",
    "soccer/usa.1": "MLS", "soccer/usa.nwsl": "NWSL", "soccer/eng.1": "Premier League",
    "soccer/esp.1": "La Liga", "soccer/ger.1": "Bundesliga", "soccer/ita.1": "Serie A",
    "soccer/fra.1": "Ligue 1", "soccer/mex.1": "Liga MX",
    "soccer/uefa.champions": "UEFA Champions League", "soccer/fifa.world": "FIFA World Cup",
    "racing/nascar-cup": "NASCAR Cup", "racing/irl": "IndyCar", "racing/f1": "Formula 1",
    "golf/pga": "PGA Tour",
}


def http_json(url, timeout=8):
    req = request.Request(url, headers={
        "User-Agent": "AuggmentScoreboard/1.0",
        "Accept": "application/json",
    })
    with request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def teams_for(path):
    sport, league = SLUG_OVERRIDES.get(path, (path.split("/")[0], path.split("/")[-1]))
    host = "site.web.api.espn.com" if path in WEB_API_LEAGUES else "site.api.espn.com"
    url = f"https://{host}/apis/site/v2/sports/{sport}/{league}/teams?limit=500"
    try:
        res = http_json(url)
        return res["sports"][0]["leagues"][0]["teams"]
    except Exception:
        return []


def main():
    paths = sys.argv[1:]
    out = []
    seen = set()
    for path in paths:
        label = LABELS.get(path, path.split("/")[-1].upper())
        if leagues.source_for(path) == "tsdb":
            for t in leagues.TSDB_TEAMS.get(path, []):
                value = f"{path}:{t['abbr']}"
                if value in seen:
                    continue
                seen.add(value)
                out.append({
                    "value": value,
                    "label": f"{t['name']} ({t['abbr']})",
                    "description": label,
                })
            continue
        for t in teams_for(path):
            team = t.get("team", {})
            abbr = team.get("abbreviation")
            name = team.get("displayName")
            if not abbr or not name:
                continue
            value = f"{path}:{abbr}"
            if value in seen:
                continue
            seen.add(value)
            out.append({
                "value": value,
                "label": f"{name} ({abbr})",
                "description": label,
            })
    out.sort(key=lambda x: x["label"].lower())
    print(json.dumps(out))


if __name__ == "__main__":
    main()
