#!/usr/bin/env python3
"""Fetch live/upcoming/final scores from ESPN for the Auggment Scoreboard bar widget.

Reads ~/.config/auggment/scoreboard.json (or --config PATH) and prints a single
JSON document to stdout. Uses only the Python standard library so it runs on a
stock Arch/Omarchy box without pip packages.

Config shape (all keys optional):

    {
      "timezone": "America/Chicago",
      "leagues": ["football/nfl", "basketball/nba"],
      "teams": ["football/nfl:KC", "basketball/nba:BOS"],
      "racing": {"racing/nascar-cup": ["Larson"], "racing/f1": ["Verstappen"]},
      "golf": ["Scheffler"],
      "team_colors": {"football/nfl:KC": "#E31837"},
      "days_back": 1,
      "days_ahead": 7,
      "max_games": 40
    }

Favorite teams use "<league/path>:<ABBREVIATION>" (abbreviations are those ESPN
returns for the team, e.g. KC, BOS, LAD).
"""

import argparse
import json
import os
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from urllib import request, error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leagues  # noqa: E402  (shared source metadata; see bin/leagues.py)

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None

CONFIG_PATH = os.path.expanduser("~/.config/auggment/scoreboard.json")

# path -> (sport, league) for the ESPN scoreboard endpoint. Ported from the
# Auggment-Scoreboard Flask app so both use identical ESPN slugs.
ESPN_API_PATHS = {
    "football/nfl": ("football", "nfl"),
    "football/cfl": ("football", "cfl"),
    "football/xfl": ("football", "xfl"),
    "football/college-football": ("football", "college-football"),
    "baseball/mlb": ("baseball", "mlb"),
    "baseball/college-baseball": ("baseball", "college-baseball"),
    "baseball/milb": ("baseball", "milb"),
    "basketball/nba": ("basketball", "nba"),
    "basketball/wnba": ("basketball", "wnba"),
    "basketball/euroleague": ("basketball", "euroleague"),
    "basketball/mens-college-basketball": ("basketball", "mens-college-basketball"),
    "basketball/womens-college-basketball": ("basketball", "womens-college-basketball"),
    "hockey/nhl": ("hockey", "nhl"),
    "hockey/mens-college-hockey": ("hockey", "mens-college-hockey"),
    "soccer/usa.1": ("soccer", "usa.1"),
    "soccer/usa.nwsl": ("soccer", "usa.nwsl"),
    "soccer/usa.usl.1": ("soccer", "usa.usl.1"),
    "soccer/usa.usl.l1": ("soccer", "usa.usl.l1"),
    "soccer/eng.1": ("soccer", "eng.1"),
    "soccer/eng.2": ("soccer", "eng.2"),
    "soccer/esp.1": ("soccer", "esp.1"),
    "soccer/ger.1": ("soccer", "ger.1"),
    "soccer/ita.1": ("soccer", "ita.1"),
    "soccer/fra.1": ("soccer", "fra.1"),
    "soccer/ned.1": ("soccer", "ned.1"),
    "soccer/por.1": ("soccer", "por.1"),
    "soccer/mex.1": ("soccer", "mex.1"),
    "soccer/bra.1": ("soccer", "bra.1"),
    "soccer/arg.1": ("soccer", "arg.1"),
    "soccer/uefa.champions": ("soccer", "uefa.champions"),
    "soccer/uefa.europa": ("soccer", "uefa.europa"),
    "soccer/fifa.world": ("soccer", "fifa.world"),
    "volleyball/womens-college-volleyball": ("volleyball", "womens-college-volleyball"),
    "volleyball/mens-college-volleyball": ("volleyball", "mens-college-volleyball"),
    "lacrosse/mens-college-lacrosse": ("lacrosse", "mens-college-lacrosse"),
    "lacrosse/womens-college-lacrosse": ("lacrosse", "womens-college-lacrosse"),
    "lacrosse/pll": ("lacrosse", "pll"),
    "lacrosse/nll": ("lacrosse", "nll"),
    "racing/nascar-cup": ("racing", "nascar-cup"),
    "racing/irl": ("racing", "irl"),
    "racing/f1": ("racing", "f1"),
    "golf/pga": ("golf", "pga"),
}

# Leagues that live on the site.web.api host rather than site.api.
ESPN_WEB_API_LEAGUES = {"softball/college-softball", "baseball/college-baseball"}

# Leagues where a single request (no ?dates=) returns the current slate.
ESPN_NO_DATE_LEAGUES = {
    "baseball/college-baseball", "softball/college-softball",
    "volleyball/mens-college-volleyball", "hockey/mens-college-hockey",
    "lacrosse/mens-college-lacrosse", "lacrosse/womens-college-lacrosse",
}

MOTORSPORTS_LEAGUES = {"racing/nascar-cup", "racing/irl", "racing/f1"}
GOLF_LEAGUES = {"golf/pga"}

LEAGUE_LABELS = {
    "football/nfl": "NFL", "football/cfl": "CFL", "football/xfl": "XFL",
    "football/college-football": "NCAAF",
    "baseball/mlb": "MLB", "baseball/college-baseball": "NCAABB", "baseball/milb": "MiLB",
    "basketball/nba": "NBA", "basketball/wnba": "WNBA", "basketball/euroleague": "EuroLeague",
    "basketball/mens-college-basketball": "NCAAM",
    "basketball/womens-college-basketball": "NCAAW",
    "hockey/nhl": "NHL", "hockey/mens-college-hockey": "NCAACH",
    "soccer/usa.1": "MLS", "soccer/usa.nwsl": "NWSL", "soccer/usa.usl.1": "USL",
    "soccer/usa.usl.l1": "USL1", "soccer/eng.1": "EPL", "soccer/eng.2": "Championship",
    "soccer/esp.1": "La Liga", "soccer/ger.1": "Bundesliga", "soccer/ita.1": "Serie A",
    "soccer/fra.1": "Ligue 1", "soccer/ned.1": "Eredivisie", "soccer/por.1": "Primeira",
    "soccer/mex.1": "Liga MX", "soccer/bra.1": "Brasileirão", "soccer/arg.1": "Primera",
    "soccer/uefa.champions": "UCL", "soccer/uefa.europa": "UEL", "soccer/fifa.world": "World Cup",
    "volleyball/womens-college-volleyball": "NCAAVB", "volleyball/mens-college-volleyball": "NCAAvbM",
    "lacrosse/mens-college-lacrosse": "NCAALAX", "lacrosse/womens-college-lacrosse": "NCAAwlax",
    "lacrosse/pll": "PLL", "lacrosse/nll": "NLL",
    "racing/nascar-cup": "NASCAR", "racing/irl": "IndyCar", "racing/f1": "F1",
    "golf/pga": "PGA",
}

USER_AGENT = "AuggmentScoreboard/1.0 (+https://github.com/auggnation/omarchy-auggment-scoreboard)"

# TheSportsDB free v1 API (the "3" key is their documented free test key).
TSDB_BASE = "https://www.thesportsdb.com/api/v1/json/3"


CACHE_PATH = os.path.expanduser("~/.cache/auggment/scoreboard-cache.json")
CACHE_MAX_AGE = 3600          # seconds a cached day may stand in for a failed request
_cache = {}
_cache_dirty = False
_fetch_errors = 0


def http_json(url, timeout=8, attempts=3):
    """GET json, retrying transient failures (ESPN occasionally drops a request)."""
    last = None
    for attempt in range(attempts):
        try:
            req = request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8", "replace"))
        except error.HTTPError as exc:
            last = exc
            if exc.code in (400, 401, 403, 404):
                break
        except Exception as exc:
            last = exc
        if attempt + 1 < attempts:
            time.sleep(0.4 * (attempt + 1))
    raise last


def load_cache():
    global _cache
    try:
        with open(CACHE_PATH, "r") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            _cache = data
    except Exception:
        _cache = {}


def save_cache():
    """Write the cache atomically; drop entries too old to be useful."""
    global _cache_dirty
    if not _cache_dirty:
        return
    cutoff = time.time() - CACHE_MAX_AGE
    keep = {k: v for k, v in _cache.items()
            if isinstance(v, dict) and v.get("t", 0) >= cutoff}
    try:
        os.makedirs(os.path.dirname(CACHE_PATH), mode=0o700, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CACHE_PATH), prefix=".cache.", suffix=".tmp")
        with os.fdopen(fd, "w") as fh:
            json.dump(keep, fh)
        os.replace(tmp, CACHE_PATH)
    except Exception:
        pass


def cached_events(url):
    """Return the "events" list for url. If the request still fails after retries,
    fall back to a recent cached copy so one dropped request does not make a
    team's game disappear; only raise when there is nothing to fall back on."""
    global _cache_dirty, _fetch_errors
    try:
        events = http_json(url).get("events") or []
    except Exception:
        _fetch_errors += 1
        entry = _cache.get(url)
        if isinstance(entry, dict) and time.time() - entry.get("t", 0) < CACHE_MAX_AGE:
            return entry.get("events") or []
        raise
    _cache[url] = {"t": time.time(), "events": events}
    _cache_dirty = True
    return events


def load_config(path):
    cfg = {
        "timezone": "America/Chicago",
        "leagues": [],
        "teams": [],
        "racing": {},
        "golf": [],
        "team_colors": {},
        "days_back": 1,
        "days_ahead": 7,
        "max_games": 40,
    }
    try:
        with open(path, "r") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            cfg.update(loaded)
    except FileNotFoundError:
        pass
    except Exception as exc:  # pragma: no cover
        print(json.dumps({"error": f"config: {exc}"}))
        sys.exit(0)
    return cfg


def tzinfo(name):
    if ZoneInfo is None:
        return timezone.utc
    try:
        return ZoneInfo(name)
    except Exception:
        return timezone.utc


def fetch_league(path, days_back, days_ahead, tz=None):
    sport, league = ESPN_API_PATHS.get(path, (path.split("/")[0], path.split("/")[-1]))
    host = "site.web.api.espn.com" if path in ESPN_WEB_API_LEAGUES else "site.api.espn.com"
    base = f"https://{host}/apis/site/v2/sports/{sport}/{league}/scoreboard"

    if path in ESPN_NO_DATE_LEAGUES:
        urls = [base]
    else:
        # Use the user's local date, not UTC, so "today" is correct in the evening.
        today = datetime.now(tz or timezone.utc).date()
        day = today - timedelta(days=days_back)
        end = today + timedelta(days=max(days_ahead, 1))
        urls = []
        while day <= end:
            urls.append(f"{base}?dates={day.strftime('%Y%m%d')}")
            day += timedelta(days=1)

    def one(url):
        try:
            return cached_events(url)
        except Exception:
            return []

    # One request per day, all at once (they used to run one after another, so
    # a slow day could push a refresh past its interval).
    with ThreadPoolExecutor(max_workers=min(6, len(urls))) as pool:
        results = list(pool.map(one, urls))

    events = []
    seen = set()
    for day_events in results:
        for e in day_events:
            if e.get("id") and e["id"] not in seen:
                seen.add(e["id"])
                events.append(e)
    events.sort(key=lambda e: e.get("date", ""))
    return events


def fetch_tsdb(path, days_back, days_ahead, tz=None):
    """Fetch a league from TheSportsDB (used for leagues ESPN does not carry).

    Combines the next and previous fixtures for the league and keeps only the
    ones inside the look-back / look-ahead window.
    """
    lid = leagues.TSDB_LEAGUE_IDS.get(path)
    if not lid:
        return []
    events = {}
    for endpoint in ("eventsnextleague.php", "eventspastleague.php"):
        try:
            fetched = cached_events(f"{TSDB_BASE}/{endpoint}?id={lid}")
        except Exception:
            continue
        for e in fetched:
            eid = e.get("idEvent")
            if eid and eid not in events:
                events[eid] = e

    today = datetime.now(tz or timezone.utc).date()
    lo = today - timedelta(days=days_back)
    hi = today + timedelta(days=max(days_ahead, 1))
    out = []
    for e in events.values():
        ts = e.get("strTimestamp") or ""
        try:
            dt0 = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            if dt0.tzinfo is None:
                dt0 = dt0.replace(tzinfo=timezone.utc)
            d = dt0.astimezone(tz or timezone.utc).date()
        except Exception:
            out.append(e)
            continue
        if lo <= d <= hi:
            out.append(e)
    out.sort(key=lambda e: e.get("strTimestamp") or "")
    return out


def _safe_fetch(path, days_back, days_ahead, tz=None):
    try:
        if leagues.source_for(path) == "tsdb":
            return fetch_tsdb(path, days_back, days_ahead, tz)
        return fetch_league(path, days_back, days_ahead, tz)
    except Exception:
        return []


def team_logo(team):
    if not isinstance(team, dict):
        return ""
    logos = team.get("logos") or []
    if logos and isinstance(logos[0], dict):
        return logos[0].get("href", "")
    return team.get("logo", "")


def team_color(team, override):
    if override:
        return override if override.startswith("#") else f"#{override}"
    if isinstance(team, dict) and team.get("color"):
        return f"#{team['color']}"
    return ""


def parse_team_game(path, event, cfg_favs, cfg_colors, tz):
    comp_list = event.get("competitions") or []
    if not comp_list or not comp_list[0].get("competitors"):
        return None
    comp = comp_list[0]
    competitors = comp["competitors"]
    home = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0])
    away = next((c for c in competitors if c.get("homeAway") == "away"), competitors[-1])

    status = event.get("status", {})
    stype = status.get("type", {})

    def side(c, homeAway):
        team = c.get("team", {})
        abbr = (team.get("abbreviation") or team.get("shortDisplayName")
                or team.get("displayName") or "?")
        key = f"{path.lower()}:{abbr.upper()}"
        try:
            score = int(c.get("score") or 0)
        except Exception:
            score = c.get("score", "")
        return {
            "abbr": abbr,
            "name": team.get("displayName") or abbr,
            "short_name": team.get("shortDisplayName") or abbr,
            "score": score,
            "logo": team_logo(team),
            "color": team_color(team, cfg_colors.get(key)),
            "fav": key in cfg_favs,
            "winner": c.get("winner", False),
            "home_away": homeAway,
        }

    a = side(away, "away")
    h = side(home, "home")
    state = stype.get("state", "pre")
    winner = None
    if state in ("in", "post") and isinstance(a["score"], int) and isinstance(h["score"], int):
        winner = "away" if a["score"] > h["score"] else ("home" if h["score"] > a["score"] else "tie")

    start = event.get("date", "")
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00")).astimezone(tz)
        start_local = dt.strftime("%a %-I:%M %p")
        start_full = dt.strftime("%a %b %-d, %-I:%M %p")
    except Exception:
        start_local = ""
        start_full = ""

    return {
        "kind": "game",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "state": state,
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "clock": status.get("displayClock", ""),
        "period": status.get("period", 0),
        "start": start,
        "start_local": start_local,
        "start_full": start_full,
        "name": event.get("shortName") or event.get("name", ""),
        "link": (event.get("links") or [{}])[0].get("href", ""),
        "away": a,
        "home": h,
        "is_fav": a["fav"] or h["fav"],
        "winner": winner,
    }


def parse_tsdb_game(path, event, cfg_favs, cfg_colors, tz):
    """Map a TheSportsDB event to the same shape as parse_team_game."""
    def side(home_away):
        if home_away == "home":
            name = event.get("strHomeTeam") or "?"
            tid = event.get("idHomeTeam")
            raw_score = event.get("intHomeScore")
            logo = event.get("strHomeTeamBadge") or ""
        else:
            name = event.get("strAwayTeam") or "?"
            tid = event.get("idAwayTeam")
            raw_score = event.get("intAwayScore")
            logo = event.get("strAwayTeamBadge") or ""
        abbr = leagues.tsdb_abbr(tid, name)
        key = f"{path.lower()}:{abbr.upper()}"
        try:
            score = int(raw_score)
        except Exception:
            score = 0
        return {
            "abbr": abbr,
            "name": name,
            "short_name": abbr,
            "score": score,
            "logo": logo,
            "color": team_color(None, cfg_colors.get(key)),
            "fav": key in cfg_favs,
            "winner": False,
            "home_away": home_away,
        }

    a = side("away")
    h = side("home")

    status = (event.get("strStatus") or "NS").upper()
    if status in ("FT", "AET", "PEN", "FINAL", "AFTER EXTRA TIME"):
        state = "post"
    elif status in ("NS", "TBD", "POSTPONED", "POSTP", "CANCELED", "CANC", "PST", "SUSP"):
        state = "pre"
    else:
        state = "in"

    winner = None
    if state == "post":
        if a["score"] > h["score"]:
            winner = "away"
            a["winner"] = True
        elif h["score"] > a["score"]:
            winner = "home"
            h["winner"] = True
        else:
            winner = "tie"

    start = event.get("strTimestamp") or ""
    start_local = start_full = ""
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        dt = dt.astimezone(tz)
        start_local = dt.strftime("%a %-I:%M %p")
        start_full = dt.strftime("%a %b %-d, %-I:%M %p")
    except Exception:
        pass

    if state == "in":
        detail = event.get("strProgress") or "LIVE"
    elif state == "post":
        detail = "Final"
    else:
        detail = start_full or (event.get("strTime") or "")

    return {
        "kind": "game",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "state": state,
        "detail": detail,
        "clock": "",
        "period": int(event.get("intRound") or 0) if str(event.get("intRound") or "").isdigit() else 0,
        "start": start,
        "start_local": start_local,
        "start_full": start_full,
        "name": event.get("strEvent") or "",
        "link": "",
        "away": a,
        "home": h,
        "is_fav": a["fav"] or h["fav"],
        "winner": winner,
    }


def parse_race(path, event, fav_names, allowed):
    status = event.get("status", {})
    stype = status.get("type", {})
    comp_list = event.get("competitions") or []
    competitors = comp_list[0].get("competitors", []) if comp_list else []

    def order_key(c):
        try:
            return int(c.get("order", 999))
        except Exception:
            return 999

    ordered = [c for c in competitors if c.get("order") is not None] or competitors
    ordered = sorted(ordered, key=order_key)

    def is_fav(athlete, car):
        full = (athlete.get("displayName", "") or "").lower()
        return any(f in full or f == (car or "").lower() for f in fav_names)

    drivers = []
    for c in ordered[:10]:
        athlete = c.get("athlete", {})
        name = athlete.get("shortName") or athlete.get("displayName") or "—"
        car = athlete.get("jersey", "")
        drivers.append({
            "pos": c.get("order") or c.get("score", "?"),
            "name": name,
            "car": car,
            "fav": is_fav(athlete, car),
        })
    if fav_names:
        for c in ordered[10:]:
            athlete = c.get("athlete", {})
            car = athlete.get("jersey", "")
            if is_fav(athlete, car):
                name = athlete.get("shortName") or athlete.get("displayName") or "—"
                drivers.append({"pos": c.get("order") or c.get("score", "?"), "name": name,
                                "car": car, "fav": True})

    return {
        "kind": "race",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "name": event.get("shortName") or event.get("name", "Race"),
        "state": stype.get("state", "pre"),
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "is_fav": any(d.get("fav") for d in drivers),
        "drivers": drivers,
    }


def parse_golf(path, event, fav_names):
    status = event.get("status", {})
    stype = status.get("type", {})
    comp_list = event.get("competitions") or []
    competitors = comp_list[0].get("competitors", []) if comp_list else []

    def pos_key(c):
        pos = (c.get("status", {}).get("position", {}) or {}).get("id", "")
        try:
            return int(pos)
        except Exception:
            return 999

    active = [c for c in competitors
              if (c.get("status", {}).get("type", {}) or {}).get("state") not in ("cut", "wd", "dq")]
    ordered = sorted(active or competitors, key=pos_key)

    def is_fav(name):
        full = (name or "").lower()
        return any(f in full for f in fav_names)

    golfers = []
    for c in ordered[:10]:
        athlete = c.get("athlete", {})
        full_name = athlete.get("displayName", "")
        golfers.append({
            "pos": (c.get("status", {}).get("position", {}) or {}).get("displayName", "?"),
            "name": athlete.get("shortName") or full_name or "—",
            "strokes": c.get("score", "—"),
            "fav": is_fav(full_name),
        })
    if fav_names:
        for c in ordered[10:]:
            athlete = c.get("athlete", {})
            if is_fav(athlete.get("displayName", "")):
                golfers.append({
                    "pos": (c.get("status", {}).get("position", {}) or {}).get("displayName", "?"),
                    "name": athlete.get("shortName") or athlete.get("displayName", "—"),
                    "strokes": c.get("score", "—"),
                    "fav": True,
                })

    return {
        "kind": "golf",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, "PGA"),
        "name": event.get("shortName") or event.get("name", "Tournament"),
        "state": stype.get("state", "pre"),
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "is_fav": any(g.get("fav") for g in golfers),
        "golfers": golfers,
    }


def build(cfg):
    tz = tzinfo(cfg.get("timezone", "America/Chicago"))
    days_back = int(cfg.get("days_back", 1))
    days_ahead = int(cfg.get("days_ahead", 7))
    team_windows = cfg.get("days_ahead_teams", {}) or {}

    def window_for(path):
        """A league must be fetched far enough for its longest per-team window."""
        eff = days_ahead
        prefix = path.lower() + ":"
        for k, v in team_windows.items():
            if isinstance(k, str) and k.lower().startswith(prefix):
                try:
                    eff = max(eff, int(v))
                except Exception:
                    pass
        return eff

    fav_set = set()
    for entry in cfg.get("teams", []):
        if isinstance(entry, str) and ":" in entry:
            lp, abbr = entry.rsplit(":", 1)
            fav_set.add(f"{lp.lower()}:{abbr.upper()}")
    colors = cfg.get("team_colors", {}) or {}
    racing = cfg.get("racing", {}) or {}
    golf_favs = [str(n).strip().lower() for n in cfg.get("golf", []) if str(n).strip()]

    games, races, golf = [], [], []
    league_paths = [p for p in cfg.get("leagues", []) if isinstance(p, str)]
    load_cache()
    with ThreadPoolExecutor(max_workers=min(4, max(1, len(league_paths)))) as pool:
        fetched = list(pool.map(lambda p: (p, _safe_fetch(p, days_back, window_for(p), tz)), league_paths))
    save_cache()
    for path, events in fetched:
        for event in events:
            try:
                if path in MOTORSPORTS_LEAGUES:
                    favs = [str(n).strip().lower() for n in racing.get(path, []) if str(n).strip()]
                    races.append(parse_race(path, event, favs, MOTORSPORTS_LEAGUES))
                elif path in GOLF_LEAGUES:
                    golf.append(parse_golf(path, event, golf_favs))
                elif leagues.source_for(path) == "tsdb":
                    g = parse_tsdb_game(path, event, fav_set, colors, tz)
                    if g:
                        games.append(g)
                else:
                    g = parse_team_game(path, event, fav_set, colors, tz)
                    if g:
                        games.append(g)
            except Exception:
                continue

    def sort_key(g):
        return (0 if g["is_fav"] else 1, {"in": 0, "pre": 1, "post": 2}.get(g["state"], 3),
                g.get("start", ""))

    games.sort(key=sort_key)
    max_games = int(cfg.get("max_games", 40))
    return {
        "updated": datetime.now(tz).isoformat(),
        "timezone": cfg.get("timezone"),
        "counts": {"games": len(games), "races": len(races), "golf": len(golf)},
        "fetch_errors": _fetch_errors,
        "games": games[:max_games],
        "races": races,
        "golf": golf,
        "has_favorites": bool(fav_set) or bool(racing) or bool(golf_favs),
    }


def main():
    ap = argparse.ArgumentParser(description="Fetch ESPN scores for Auggment Scoreboard")
    ap.add_argument("--config", default=CONFIG_PATH)
    ap.add_argument("--pretty", action="store_true")
    args = ap.parse_args()
    cfg = load_config(args.config)
    try:
        result = build(cfg)
    except Exception as exc:  # pragma: no cover
        result = {"error": str(exc), "games": [], "races": [], "golf": []}
    print(json.dumps(result, indent=2 if args.pretty else None))


if __name__ == "__main__":
    main()
