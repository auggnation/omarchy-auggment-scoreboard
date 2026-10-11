"""Shared league source metadata for the Auggment Scoreboard.

Most leagues come from ESPN's scoreboard feed. A few (currently the CFL) are
not carried by ESPN, so they are served by TheSportsDB (free v1 API, key "3").

The fetcher (fetch-scores.py) and the team helpers (list-teams.py,
list-all-teams.py) both import this module so that the favourite keys
("<league/path>:<ABBR>") line up everywhere.
"""

# league path -> TheSportsDB league id
TSDB_LEAGUE_IDS = {
    "football/cfl": "4405",
}

# Canonical team lists for TheSportsDB leagues. TheSportsDB's own
# strTeamShort values are inconsistent, so we ship the standard abbreviations
# fans expect (BC, CGY, ... ) and match them back to events by team id.
TSDB_TEAMS = {
    "football/cfl": [
        {"id": "135006", "abbr": "BC", "name": "BC Lions"},
        {"id": "135007", "abbr": "CGY", "name": "Calgary Stampeders"},
        {"id": "135008", "abbr": "EDM", "name": "Edmonton Elks"},
        {"id": "135002", "abbr": "HAM", "name": "Hamilton Tiger-Cats"},
        {"id": "135003", "abbr": "MTL", "name": "Montreal Alouettes"},
        {"id": "135004", "abbr": "OTT", "name": "Ottawa Redblacks"},
        {"id": "135009", "abbr": "SSK", "name": "Saskatchewan Roughriders"},
        {"id": "135005", "abbr": "TOR", "name": "Toronto Argonauts"},
        {"id": "135010", "abbr": "WPG", "name": "Winnipeg Blue Bombers"},
    ],
}

# Lookup tables built once from TSDB_TEAMS.
_TSDB_ABBR_BY_ID = {}
_TSDB_ABBR_BY_NAME = {}
for _path, _teams in TSDB_TEAMS.items():
    for _t in _teams:
        _TSDB_ABBR_BY_ID[_t["id"]] = _t["abbr"]
        _TSDB_ABBR_BY_NAME[_t["name"]] = _t["abbr"]


def source_for(path):
    """Return the data source ("esports" / "tsdb" / "espn") for a league path."""
    return "tsdb" if path in TSDB_LEAGUE_IDS else "espn"


def tsdb_abbr(team_id, name):
    """Resolve a TheSportsDB team to our canonical abbreviation."""
    if team_id is not None and str(team_id) in _TSDB_ABBR_BY_ID:
        return _TSDB_ABBR_BY_ID[str(team_id)]
    if name in _TSDB_ABBR_BY_NAME:
        return _TSDB_ABBR_BY_NAME[name]
    return "".join(w[0] for w in (name or "?").split() if w)[:3].upper() or "?"
