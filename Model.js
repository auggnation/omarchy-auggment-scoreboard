.pragma library

// League catalogue shared by the settings picker and the fetcher fallback.
// `path` is the "<sport>/<league>" slug used by the ESPN scoreboard endpoint
// and by the config file.
var LEAGUES = [
  { path: "football/nfl", label: "NFL", group: "Football" },
  { path: "football/college-football", label: "NCAA Football", group: "Football" },
  { path: "football/cfl", label: "CFL", group: "Football" },
  { path: "football/xfl", label: "XFL", group: "Football" },

  { path: "basketball/nba", label: "NBA", group: "Basketball" },
  { path: "basketball/wnba", label: "WNBA", group: "Basketball" },
  { path: "basketball/mens-college-basketball", label: "NCAA Men's Basketball", group: "Basketball" },
  { path: "basketball/womens-college-basketball", label: "NCAA Women's Basketball", group: "Basketball" },
  { path: "basketball/euroleague", label: "EuroLeague", group: "Basketball" },

  { path: "baseball/mlb", label: "MLB", group: "Baseball" },
  { path: "baseball/college-baseball", label: "NCAA Baseball", group: "Baseball" },
  { path: "baseball/milb", label: "MiLB", group: "Baseball" },

  { path: "hockey/nhl", label: "NHL", group: "Hockey" },
  { path: "hockey/mens-college-hockey", label: "NCAA Hockey", group: "Hockey" },

  { path: "soccer/usa.1", label: "MLS", group: "Soccer" },
  { path: "soccer/usa.nwsl", label: "NWSL", group: "Soccer" },
  { path: "soccer/eng.1", label: "Premier League", group: "Soccer" },
  { path: "soccer/esp.1", label: "La Liga", group: "Soccer" },
  { path: "soccer/ger.1", label: "Bundesliga", group: "Soccer" },
  { path: "soccer/ita.1", label: "Serie A", group: "Soccer" },
  { path: "soccer/fra.1", label: "Ligue 1", group: "Soccer" },
  { path: "soccer/mex.1", label: "Liga MX", group: "Soccer" },
  { path: "soccer/uefa.champions", label: "UEFA Champions League", group: "Soccer" },
  { path: "soccer/fifa.world", label: "FIFA World Cup", group: "Soccer" },

  { path: "racing/nascar-cup", label: "NASCAR Cup", group: "Racing" },
  { path: "racing/irl", label: "IndyCar", group: "Racing" },
  { path: "racing/f1", label: "Formula 1", group: "Racing" },

  { path: "golf/pga", label: "PGA Tour", group: "Golf" }
]

function groupOrder() {
  return ["Football", "Basketball", "Baseball", "Hockey", "Soccer", "Racing", "Golf"]
}

function leaguesInGroup(group) {
  var out = []
  for (var i = 0; i < LEAGUES.length; i++) {
    if (LEAGUES[i].group === group) out.push(LEAGUES[i])
  }
  return out
}

function labelFor(path) {
  for (var i = 0; i < LEAGUES.length; i++) {
    if (LEAGUES[i].path === path) return LEAGUES[i].label
  }
  var parts = String(path).split("/")
  return parts[parts.length - 1].toUpperCase()
}

function isRacing(path) {
  return path === "racing/nascar-cup" || path === "racing/irl" || path === "racing/f1"
}

function isGolf(path) {
  return path === "golf/pga"
}

function stateRank(state) {
  if (state === "in") return 0
  if (state === "pre") return 1
  if (state === "post") return 2
  return 3
}
