import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Auggment Scoreboard — a lightweight live-scores bar widget.
//
// Left click opens the scores view (rotating through your favorites), right
// click opens settings, middle click refreshes now. Scores come from ESPN via
// the bundled bin/fetch-scores.py; the config lives at
// ~/.config/auggment/scoreboard.json.
Panel {
  id: root
  moduleName: "io.github.auggnation.auggment-scoreboard"
  ipcTarget: "io.github.auggnation.auggment-scoreboard"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/auggment/scoreboard.json"
  readonly property string binDir: Qt.resolvedUrl("bin").toString().replace("file://", "")
  readonly property string fetchScript: binDir + "/fetch-scores.py"
  readonly property string listAllTeamsScript: binDir + "/list-all-teams.py"
  readonly property string saveConfigScript: binDir + "/save-config.py"

  property var config: root.defaultConfig()
  property var scores: ({})
  property string mode: "current"
  property int rotateIndex: 0
  property bool loading: false
  property bool dirty: false
  property bool savePending: false
  readonly property string buildTag: "7"
  property string lastSaved: ""
  property double lastClosedAt: 0
  property string lastClosedMode: ""
  property int configRev: 0   // bumps when the config file is (re)loaded; text fields re-sync on it
  property bool refreshQueued: false
  property string statusText: ""

  // Colours for the four game states; overridable via config.state_colors.
  readonly property var defaultStateColors: ({
    live: "#22C55E", today: "#F59E0B", this_week: "#60A5FA", final: "#9CA3AF"
  })
  readonly property var stateColorRows: [
    { key: "live", label: "Game in progress" },
    { key: "today", label: "Game today" },
    { key: "this_week", label: "Game later this week" },
    { key: "final", label: "Game over" }
  ]
  readonly property string updatedText: {
    var u = scores && scores.updated ? Date.parse(scores.updated) : NaN
    return isNaN(u) ? "" : Qt.formatTime(new Date(u), "h:mm AP")
  }
  readonly property var swatchPalette: ["#E31837", "#F97316", "#F59E0B", "#22C55E", "#14B8A6", "#3B82F6",
                                         "#6366F1", "#A855F7", "#EC4899", "#FFFFFF", "#9CA3AF", "#111827"]
  readonly property bool showBarLogos: config.bar_logos !== false
  readonly property bool cycleLeagues: config.league_in_cycle === true

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function defaultConfig() {
    return {
      timezone: "America/Chicago",
      leagues: ["football/nfl"],
      teams: [],
      racing: {},
      golf: [],
      team_colors: {},
      days_ahead_teams: {},
      days_back: 1,
      days_ahead: 7,
      refresh_seconds: 60,
      rotate_seconds: 6,
      max_games: 40,
      state_colors: {},
      bar_logos: true,
      league_in_cycle: false,
      position: "right",
      positioned: false
    }
  }

  function setConfig(key, value) {
    var copy = {}
    for (var k in config) copy[k] = config[k]
    copy[key] = value
    config = copy
    dirty = true
    autosaveTimer.restart()
  }

  // "#RRGGBB" (leading # optional) -> normalized string, "" for blank, null if invalid.
  function normalizeHex(v) {
    var s = String(v || "").trim()
    if (s === "") return ""
    if (s.charAt(0) !== "#") s = "#" + s
    return /^#[0-9a-fA-F]{6}$/.test(s) ? s.toUpperCase() : null
  }

  function setColorMap(configKey, mapKey, text) {
    var n = normalizeHex(text)
    if (n === null) { statusText = "Colors must look like #RRGGBB"; return }
    var colors = {}
    var existing = config[configKey] || {}
    for (var k in existing) colors[k] = existing[k]
    if (n === "") delete colors[mapKey]
    else colors[mapKey] = n
    setConfig(configKey, colors)
  }

  function applyConfigText(txt) {
    var parsed = null
    try { parsed = JSON.parse(String(txt || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      config = defaultConfig()
      saveConfig()
      return
    }
    var base = defaultConfig()
    for (var k in parsed) base[k] = parsed[k]
    config = base
    configRev++
  }

  // Settings are written to ~/.config/auggment/scoreboard.json automatically
  // (debounced after every change, and when the panel closes). The JSON is
  // passed as an argument so nothing depends on a stdin pipe being closed.
  function saveConfig() {
    autosaveTimer.stop()
    if (saveProc.running) { savePending = true; return }
    saveProc.command = ["python3", saveConfigScript, "--data", JSON.stringify(config)]
    dirty = false
    saveProc.running = true
  }

  function refresh() {
    if (fetchProc.running) { refreshQueued = true; return }
    loading = true
    statusText = ""
    fetchProc.running = true
  }

  // ---- bar placement -----------------------------------------------------

  readonly property var positionOptions: [
    { value: "left", label: "Top left" },
    { value: "center", label: "Middle" },
    { value: "right", label: "Top right" }
  ]

  function currentPosition() {
    var p = config.position
    return (p === "left" || p === "center" || p === "right") ? p : "right"
  }

  function setPosition(section) {
    setConfig("position", section)
    setConfig("positioned", true)
    barProc.command = ["omarchy", "bar", "move", root.moduleName, "--section", section]
    if (!barProc.running) barProc.running = true
    saveConfig()
  }

  // ---- per-team look-ahead ----------------------------------------------

  function teamAhead(key) {
    var overrides = config.days_ahead_teams || {}
    var v = overrides[key]
    if (v === undefined || v === null || v === "") return (config.days_ahead || 7)
    return v
  }

  function setTeamAhead(key, value) {
    var overrides = {}
    var existing = config.days_ahead_teams || {}
    for (var k in existing) overrides[k] = existing[k]
    overrides[key] = value
    setConfig("days_ahead_teams", overrides)
  }

  function daysUntil(iso) {
    if (!iso) return 0
    var t = Date.parse(iso)
    if (isNaN(t)) return 0
    return Math.ceil((t - Date.now()) / 86400000)
  }

  function gameVisible(g) {
    if (!g || !g.is_fav) return false
    if (g.state !== "pre") return true
    var du = daysUntil(g.start)
    var sides = [g.away, g.home]
    for (var i = 0; i < sides.length; i++) {
      var s = sides[i]
      if (s && s.fav && du <= teamAhead(g.league_path + ":" + s.abbr)) return true
    }
    return false
  }

  function removeTeam(key) {
    var teams = (config.teams || []).filter(function(t) { return t !== key })
    setConfig("teams", teams)
    var overrides = {}
    var existing = config.days_ahead_teams || {}
    for (var k in existing) if (k !== key) overrides[k] = existing[k]
    setConfig("days_ahead_teams", overrides)
  }

  // ---- tiles for the bar rotation ----------------------------------------
  // Order: one tile per favourite team (config order), favourite racing/golf,
  // and finally the league scoreboard(s). The bar and the Current game view
  // both show tiles[rotateIndex], so they always match.

  function normKey(k) {
    var s = String(k || "")
    var i = s.lastIndexOf(":")
    if (i < 0) return s.toLowerCase()
    return s.substring(0, i).toLowerCase() + ":" + s.substring(i + 1).toUpperCase()
  }

  function gameInvolves(g, key) {
    var sides = [g.away, g.home]
    for (var i = 0; i < sides.length; i++) {
      var s = sides[i]
      if (s && s.fav && (String(g.league_path).toLowerCase() + ":" + String(s.abbr).toUpperCase()) === key) return true
    }
    return false
  }

  // Live beats upcoming beats final; soonest upcoming, most recent final.
  function betterGame(a, b) {
    var ra = Model.stateRank(a.state)
    var rb = Model.stateRank(b.state)
    if (ra !== rb) return ra < rb
    var ta = Date.parse(a.start)
    var tb = Date.parse(b.start)
    if (isNaN(ta) || isNaN(tb)) return false
    return a.state === "post" ? ta > tb : ta < tb
  }

  // A favourite team with no game inside its look-ahead window still gets a
  // slide, so a team you add always appears right away.
  function teamPlaceholder(key) {
    var favs = (scores && scores.favorites) || []
    var f = null
    for (var i = 0; i < favs.length; i++) if (favs[i].key === key) { f = favs[i]; break }
    var idx = key.lastIndexOf(":")
    var lp = key.substring(0, idx)
    var abbr = key.substring(idx + 1)
    return {
      kind: "team", fav: true, state: "pre", team_key: key, league_path: lp,
      league_label: f ? f.league_label : Model.labelFor(lp),
      abbr: abbr, name: f ? f.name : abbr, logo: f ? f.logo : "",
      color: (f && f.color) ? f.color : "", days: teamAhead(key)
    }
  }

  function favoriteGameTiles() {
    var games = (scores && scores.games) || []
    var teams = config.teams || []
    var out = []
    var seen = {}
    for (var i = 0; i < teams.length; i++) {
      var key = normKey(teams[i])
      var best = null
      for (var j = 0; j < games.length; j++) {
        var g = games[j]
        if (!gameVisible(g) || !gameInvolves(g, key)) continue
        if (!best || betterGame(g, best)) best = g
      }
      if (best) {
        var id = best.league_path + "|" + best.name + "|" + best.start
        if (!seen[id]) { seen[id] = true; out.push(best) }
      } else {
        out.push(teamPlaceholder(key))
      }
    }
    return out
  }

  function leagueTiles() {
    if (!cycleLeagues) return []
    var games = (scores && scores.games) || []
    var paths = (config.leagues || []).filter(function(p) { return !Model.isRacing(p) && !Model.isGolf(p) })
    var out = []
    for (var i = 0; i < paths.length; i++) {
      var lp = paths[i]
      var list = games.filter(function(g) { return g.league_path === lp })
      if (list.length === 0) continue
      list.sort(function(a, b) {
        var d = Model.stateRank(a.state) - Model.stateRank(b.state)
        return d !== 0 ? d : String(a.start).localeCompare(String(b.start))
      })
      var live = list.filter(function(g) { return g.state === "in" }).length
      out.push({ kind: "league", league_path: lp, league_label: list[0].league_label || Model.labelFor(lp),
                 games: list, live: live, state: live > 0 ? "in" : "pre" })
    }
    return out
  }

  readonly property var tiles: {
    var data = scores || {}
    var out = favoriteGameTiles()
    var races = data.races || []
    for (var j = 0; j < races.length; j++) if (races[j].is_fav) out.push(races[j])
    var golf = data.golf || []
    for (var g = 0; g < golf.length; g++) if (golf[g].is_fav) out.push(golf[g])
    var lt = leagueTiles()
    for (var k = 0; k < lt.length; k++) out.push(lt[k])
    return out
  }
  readonly property int safeIndex: tiles.length > 0 ? ((rotateIndex % tiles.length) + tiles.length) % tiles.length : 0
  readonly property var currentTile: tiles.length > 0 ? tiles[safeIndex] : null
  readonly property var barGame: (currentTile && currentTile.kind === "game") ? currentTile : null
  readonly property bool hasFavorites: {
    if ((config.teams || []).length > 0) return true
    if ((config.golf || []).length > 0) return true
    var racing = config.racing || {}
    for (var k in racing) if ((racing[k] || []).length > 0) return true
    return false
  }

  // ---- colours ------------------------------------------------------------

  function stateColorFor(cat) {
    var v = (config.state_colors || {})[cat]
    return v ? v : defaultStateColors[cat]
  }

  function gameCategory(g) {
    if (!g) return "this_week"
    if (g.state === "in") return "live"
    if (g.state === "post") return "final"
    var t = Date.parse(g.start)
    if (isNaN(t)) return "this_week"
    var d = new Date(t)
    var n = new Date()
    var same = d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate()
    return same ? "today" : "this_week"
  }

  function tileCategory(t) {
    if (!t) return "this_week"
    if (t.kind === "game") return gameCategory(t)
    if (t.kind === "league") return t.live > 0 ? "live" : "this_week"
    if (t.kind === "team") return "final"
    if (t.state === "in") return "live"
    if (t.state === "post") return "final"
    return "this_week"
  }

  function categoryLabel(cat) {
    if (cat === "live") return "LIVE"
    if (cat === "today") return "TODAY"
    if (cat === "final") return "FINAL"
    return "UPCOMING"
  }

  function stateColor(t) { return stateColorFor(tileCategory(t)) }
  function gameAccent(g) { return stateColorFor(gameCategory(g)) }

  // Bar text colour for non-game tiles: the state colour.
  readonly property color currentColor: currentTile ? stateColor(currentTile) : fg

  // Favourite teams use their colour (custom if set, else ESPN's).
  function teamColor(side, fallback) {
    if (side && side.fav && side.color) return side.color
    return fallback
  }

  // Left click -> current game, right click -> settings. Clicking the same
  // view again closes the dropdown; clicking the other one just switches.
  function showMode(m) {
    if (opened && mode === m) { close(); return }
    // The panel can close itself on the press that reaches us (click-away);
    // treat that press as the "close" click instead of reopening.
    if (!opened && lastClosedMode === m && (Date.now() - lastClosedAt) < 350) return
    mode = m
    if (!opened) open()
  }

  function rotateNext() {
    if (tiles.length > 1) { rotateIndex = (safeIndex + 1) % tiles.length; rotateTimer.restart() }
  }

  function rotatePrev() {
    if (tiles.length > 1) { rotateIndex = (safeIndex - 1 + tiles.length) % tiles.length; rotateTimer.restart() }
  }

  function tileTitle(t) {
    if (!t) return ""
    if (t.kind === "league") return t.league_label + " scoreboard"
    if (t.kind === "team") return t.name
    if (t.kind === "game") {
      var s = (t.away && t.away.fav) ? t.away : ((t.home && t.home.fav) ? t.home : null)
      return s ? s.name : (t.away.abbr + " @ " + t.home.abbr)
    }
    return t.name || ""
  }

  function shortTime(s) {
    var t = String(s || "")
    var sp = t.indexOf(" ")
    return sp >= 0 ? t.substring(sp + 1) : t
  }

  function barLabel() {
    var t = currentTile
    if (!t) return loading ? "…" : ((config.teams || []).length === 0 ? "Pick teams" : "—")
    if (t.kind === "league") {
      return t.league_label + " · " + (t.live > 0 ? t.live + " live" : t.games.length + " games")
    }
    if (t.kind === "team") return t.abbr + " · no game"
    if (t.kind === "race" || t.kind === "golf") {
      var d = String(t.detail || "")
      if (d.length > 10) d = d.substring(0, 10)
      return (t.league_label || "") + (d ? " " + d : "")
    }
    var a = t.away || {}
    var h = t.home || {}
    if (t.state === "pre") return a.abbr + "@" + h.abbr
    return a.abbr + " " + a.score + "–" + h.score + " " + h.abbr
  }

  function gameDetail(g) {
    if (!g) return ""
    if (g.state === "in") {
      if (g.detail) return g.detail
      if (g.clock) return g.clock + (g.period ? " · P" + g.period : "")
      return "LIVE"
    }
    if (g.state === "post") return "Final"
    return g.start_full || shortTime(g.start_local)
  }

  readonly property string summary: {
    var d = scores || {}
    var c = d.counts || {}
    var n = (c.games || 0) + (c.races || 0) + (c.golf || 0)
    if (!n) return loading ? "Loading…" : "No games in the look-ahead window"
    return n + " games · looking " + (config.days_ahead || 0) + " days ahead"
  }

  // Grouped lists for the scores view.
  readonly property var favGames: (scores.games || []).filter(function(g) { return gameVisible(g) })
  readonly property var liveGames: (scores.games || []).filter(function(g) { return !g.is_fav && g.state === "in" })
  readonly property var preGames: (scores.games || []).filter(function(g) { return !g.is_fav && g.state === "pre" })
  readonly property var postGames: (scores.games || []).filter(function(g) { return !g.is_fav && g.state === "post" })

  // Racing / golf favorites as a single flat list, stored back per league.
  function racingLeagues() {
    return (config.leagues || []).filter(function(p) { return Model.isRacing(p) })
  }
  function racingDriversText() {
    var seen = {}
    var out = []
    var racing = config.racing || {}
    for (var k in racing) {
      var arr = racing[k] || []
      for (var i = 0; i < arr.length; i++) {
        var n = String(arr[i] || "").trim()
        if (n && !seen[n.toLowerCase()]) { seen[n.toLowerCase()] = true; out.push(n) }
      }
    }
    return out.join(", ")
  }
  function applyRacing(text) {
    var names = String(text || "").split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
    var dict = {}
    // Store the names under every racing series, not just the selected ones,
    // so they are kept even if a series is selected later.
    for (var i = 0; i < Model.LEAGUES.length; i++) {
      if (Model.isRacing(Model.LEAGUES[i].path)) dict[Model.LEAGUES[i].path] = names
    }
    setConfig("racing", dict)
  }
  readonly property bool racingNamesMissingLeague: racingDriversText() !== "" && racingLeagues().length === 0
  readonly property bool golfNamesMissingLeague: (config.golf || []).length > 0 && (config.leagues || []).indexOf("golf/pga") < 0
  function applyGolf(text) {
    var names = String(text || "").split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
    setConfig("golf", names)
  }

  // -------------------------------------------------------------------------
  // Bar button
  // -------------------------------------------------------------------------
  Item {
    id: button
    anchors.fill: parent
    implicitWidth: barRow.implicitWidth + Style.space(12)
    implicitHeight: Math.max(barRow.implicitHeight, Style.space(16)) + Style.space(8)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: barMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent)
             : (root.currentTile ? Qt.rgba(root.currentColor.r, root.currentColor.g, root.currentColor.b, 0.18) : "transparent")
      border.width: root.currentTile ? 1 : 0
      border.color: Qt.rgba(root.currentColor.r, root.currentColor.g, root.currentColor.b, 0.6)
    }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      // ---- game tile: [logo] AWAY 24–17 HOME [logo] ----
      Image {
        visible: root.showBarLogos && !!root.barGame && !!root.barGame.away.logo
        width: Style.space(16); height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        sourceSize.width: 48; sourceSize.height: 48
        source: visible ? root.barGame.away.logo : ""
      }
      Text {
        visible: !!root.barGame
        anchors.verticalCenter: parent.verticalCenter
        text: root.barGame ? root.barGame.away.abbr : ""
        color: root.teamColor(root.barGame ? root.barGame.away : null, root.fg)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        visible: !!root.barGame
        anchors.verticalCenter: parent.verticalCenter
        text: !root.barGame ? "" : (root.barGame.state === "pre" ? "@" : root.barGame.away.score + "–" + root.barGame.home.score)
        color: root.currentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        visible: !!root.barGame
        anchors.verticalCenter: parent.verticalCenter
        text: root.barGame ? root.barGame.home.abbr : ""
        color: root.teamColor(root.barGame ? root.barGame.home : null, root.fg)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Image {
        visible: root.showBarLogos && !!root.barGame && !!root.barGame.home.logo
        width: Style.space(16); height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        sourceSize.width: 48; sourceSize.height: 48
        source: visible ? root.barGame.home.logo : ""
      }

      // ---- league / race / golf tile, or nothing to show ----
      Text {
        visible: !root.barGame
        anchors.verticalCenter: parent.verticalCenter
        text: root.barLabel()
        color: root.currentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) root.showMode("settings")
        else if (mouse.button === Qt.MiddleButton) root.refresh()
        else root.showMode("current")
      }
      // Scroll over the bar item to step through games without opening it.
      onWheel: function(wheel) {
        if (wheel.angleDelta.y > 0) root.rotatePrev()
        else if (wheel.angleDelta.y < 0) root.rotateNext()
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.showMode("current") }
    function scores(): void { root.mode = "scores"; root.open() }
    function current(): void { root.mode = "current"; root.open() }
    function next(): void { root.rotateNext() }
    function prev(): void { root.rotatePrev() }
    function settings(): void { root.mode = "settings"; root.open() }
    function refresh(): void { root.refresh() }
  }

  // -------------------------------------------------------------------------
  // Popup
  // -------------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.mode === "current" ? 500 : 420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(root.mode === "current" ? 640 : 560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.mode = root.mode === "settings" ? "current" : "settings"
        else if ((t === "n" || t === "N") && root.mode === "current") root.rotateNext()
        else if ((t === "p" || t === "P") && root.mode === "current") root.rotatePrev()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Auggment Scoreboard"
            meta: root.statusText !== "" ? root.statusText : root.summary
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰅢"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "Game"
              selected: root.mode === "current"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.mode = "current"
            }
            Button {
              text: "Scores"
              selected: root.mode === "scores"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.mode = "scores"
            }
            Button {
              text: "Next ▸"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: { root.mode = "current"; root.rotateNext() }
            }
            Button {
              text: "Settings"
              selected: root.mode === "settings"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.mode = "settings"
            }
            Item { Layout.fillWidth: true }
            Button {
              text: root.loading ? "…" : "⟳"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }
          }

          PanelSeparator { foreground: root.fg }

          // ---------------------- SCORES VIEW ----------------------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.mode === "scores"

            Text {
              width: parent.width
              visible: root.tiles.length === 0
              text: root.loading ? "Loading scores…" : "No games found. Add leagues and teams in Settings."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            ScoreSection { title: "YOUR TEAMS"; games: root.favGames; rootWidth: column.width }
            ScoreSection { title: "LEAGUE · LIVE"; games: root.liveGames; rootWidth: column.width }
            ScoreSection { title: "LEAGUE · UPCOMING"; games: root.preGames; rootWidth: column.width }
            ScoreSection { title: "LEAGUE · FINAL"; games: root.postGames; rootWidth: column.width }
            LeaderSection { title: "RACING"; items: (root.scores.races || []); rootWidth: column.width }
            LeaderSection { title: "GOLF"; items: (root.scores.golf || []); rootWidth: column.width }
          }

          // ---------------------- CURRENT GAME VIEW ----------------------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.mode === "current"

            Text {
              width: parent.width
              visible: !root.currentTile
              text: root.loading ? "Loading…" : "No favorite teams yet. Open Settings to pick leagues and favorites."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            BigGame {
              visible: !!root.currentTile && root.currentTile.kind === "game"
              game: (root.currentTile && root.currentTile.kind === "game") ? root.currentTile : null
            }
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: !!root.currentTile && root.currentTile.kind === "team"
              TeamBlock {
                width: parent.width
                side: (root.currentTile && root.currentTile.kind === "team") ? root.currentTile : null
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: (root.currentTile && root.currentTile.kind === "team")
                      ? (root.loading ? "Checking the schedule…" : "No " + root.currentTile.league_label + " game in the next " + root.currentTile.days + " days. Raise this team's look-ahead in Settings to see further.")
                      : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
            ScoreSection {
              title: (root.currentTile && root.currentTile.kind === "league") ? root.currentTile.league_label + " SCOREBOARD" : ""
              games: (root.currentTile && root.currentTile.kind === "league") ? root.currentTile.games : []
              rootWidth: column.width
            }
            LeaderSection {
              title: "NOW SHOWING"
              items: (root.currentTile && (root.currentTile.kind === "race" || root.currentTile.kind === "golf")) ? [root.currentTile] : []
              rootWidth: column.width
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: root.tiles.length > 1
                text: "◂ Prev"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.rotatePrev()
              }
              Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.tiles.length > 0 ? (root.safeIndex + 1) + " / " + root.tiles.length + "  ·  " + root.tileTitle(root.currentTile) : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                visible: root.tiles.length > 1
                text: "Next ▸"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.rotateNext()
              }
              Button {
                text: root.loading ? "Refreshing…" : "⟳ Refresh"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: (root.updatedText !== "" ? "Updated " + root.updatedText + " · " : "") + "build " + root.buildTag
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------------------- SETTINGS VIEW ----------------------
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.mode === "settings"

            RowLayout {
              width: parent.width
              spacing: Style.space(16)

              NumberField {
                label: "Days ahead"
                value: root.config.days_ahead || 7
                from: 0; to: 30; stepSize: 1
                foreground: root.fg
                fontFamily: root.fontFamily
                onModified: function(v) { root.setConfig("days_ahead", v) }
              }
              NumberField {
                label: "Days back"
                value: root.config.days_back || 1
                from: 0; to: 14; stepSize: 1
                foreground: root.fg
                fontFamily: root.fontFamily
                onModified: function(v) { root.setConfig("days_back", v) }
              }
              NumberField {
                label: "Rotate (s)"
                value: root.config.rotate_seconds || 6
                from: 2; to: 60; stepSize: 1
                foreground: root.fg
                fontFamily: root.fontFamily
                onModified: function(v) { root.setConfig("rotate_seconds", v) }
              }
              NumberField {
                label: "Refresh (s)"
                value: root.config.refresh_seconds || 60
                from: 15; to: 600; stepSize: 5
                foreground: root.fg
                fontFamily: root.fontFamily
                onModified: function(v) { root.setConfig("refresh_seconds", v) }
              }
            }

            PanelSeparator { foreground: root.fg }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "SPORTS / LEAGUES"; foreground: root.fg; fontFamily: root.fontFamily }
              MultiSelect {
                width: parent.width
                label: "Leagues"
                values: root.config.leagues || []
                options: Model.LEAGUES.map(function(l) { return { value: l.path, label: l.label, description: l.group } })
                placeholderText: "Search leagues…"
                emptyText: "No leagues"
                foreground: Color.popups.text
                background: Color.popups.background
                popupBorder: Color.popups.border
                accent: Color.accent
                onChanged: function(v) {
                  root.setConfig("leagues", v)
                  var teams = (root.config.teams || []).filter(function(entry) {
                    var lp = String(entry).split(":")[0]
                    return v.indexOf(lp) !== -1
                  })
                  root.setConfig("teams", teams)
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "BAR POSITION"; foreground: root.fg; fontFamily: root.fontFamily }
              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                Repeater {
                  model: root.positionOptions
                  delegate: Button {
                    required property var modelData
                    text: modelData.label
                    selected: root.currentPosition() === modelData.value
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.setPosition(modelData.value)
                  }
                }
                Item { Layout.fillWidth: true }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "FAVORITE TEAMS"; foreground: root.fg; fontFamily: root.fontFamily }
              Button {
                visible: (root.config.teams || []).length > 0
                text: "Clear all favorites"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: { root.setConfig("teams", []); root.setConfig("days_ahead_teams", {}) }
              }
              MultiSelect {
                width: parent.width
                label: "Teams"
                values: root.config.teams || []
                optionsCommand: ["python3", root.listAllTeamsScript].concat(root.config.leagues || [])
                placeholderText: "Search teams…"
                emptyText: "Pick leagues above first"
                noSelectionText: "None selected"
                foreground: Color.popups.text
                background: Color.popups.background
                popupBorder: Color.popups.border
                accent: Color.accent
                onChanged: function(v) { root.setConfig("teams", v) }
              }

              Repeater {
                model: root.config.teams || []
                delegate: RowLayout {
                  required property string modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    text: modelData
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Text {
                    text: "look-ahead"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  NumberField {
                    label: ""
                    value: root.teamAhead(modelData)
                    from: 0; to: 30; stepSize: 1
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    Layout.preferredWidth: Style.space(90)
                    onModified: function(v) { root.setTeamAhead(modelData, v) }
                  }
                  Button {
                    text: "Remove"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.removeTeam(modelData)
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "PLAYERS / DRIVERS"; foreground: root.fg; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "Comma-separated names. Racing applies to NASCAR, IndyCar and F1."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              TextField {
                id: racingField
                width: parent.width
                placeholderText: "Racing drivers (e.g. Larson, Verstappen)"
                foreground: root.fg
                Component.onCompleted: text = root.racingDriversText()
                Connections {
                  target: root
                  function onConfigRevChanged() { racingField.text = root.racingDriversText() }
                  function onOpenedChanged() { if (root.opened) racingField.text = root.racingDriversText() }
                }
                onTextEdited: root.applyRacing(text)
                onEditingFinished: root.applyRacing(text)
              }
              Text {
                width: parent.width
                visible: root.racingNamesMissingLeague
                text: "Saved, but no racing series is selected. Add NASCAR, IndyCar or Formula 1 under Leagues to see them."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              TextField {
                id: golfField
                width: parent.width
                placeholderText: "Golf players (e.g. Scheffler)"
                foreground: root.fg
                Component.onCompleted: text = (root.config.golf || []).join(", ")
                Connections {
                  target: root
                  function onConfigRevChanged() { golfField.text = (root.config.golf || []).join(", ") }
                  function onOpenedChanged() { if (root.opened) golfField.text = (root.config.golf || []).join(", ") }
                }
                onTextEdited: root.applyGolf(text)
                onEditingFinished: root.applyGolf(text)
              }
              Text {
                width: parent.width
                visible: root.golfNamesMissingLeague
                text: "Saved, but PGA Tour is not selected under Leagues."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: (root.config.teams || []).length > 0

              PanelSectionHeader { text: "TEAM COLORS"; foreground: root.fg; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "Color for this team's name in the bar and board. Leave blank to use the team's own color."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.config.teams || []
                delegate: Column {
                  id: teamColorRow
                  required property string modelData
                  width: parent.width
                  spacing: Style.space(4)
                  RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(14)
                    Layout.preferredHeight: Style.space(14)
                    radius: 3
                    color: (root.config.team_colors || {})[modelData] || "transparent"
                    border.color: root.dim
                    border.width: 1
                  }
                  Text {
                    Layout.fillWidth: true
                    text: modelData
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  TextField {
                    id: teamHex
                    Layout.preferredWidth: Style.space(110)
                    placeholderText: "#RRGGBB"
                    foreground: root.fg
                    text: (root.config.team_colors || {})[teamColorRow.modelData] || ""
                    onEditingFinished: root.setColorMap("team_colors", teamColorRow.modelData, text)
                  }
                  }
                  Swatches {
                    width: parent.width
                    onPicked: function(hex) { teamHex.text = hex; root.setColorMap("team_colors", teamColorRow.modelData, hex) }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "GAME STATE COLORS"; foreground: root.fg; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "Used for the status badge, accent and score. Hex like #22C55E; blank restores the default."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.stateColorRows
                delegate: Column {
                  id: stateColorRow
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(4)
                  RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(14)
                    Layout.preferredHeight: Style.space(14)
                    radius: 3
                    color: root.stateColorFor(modelData.key)
                    border.color: root.dim
                    border.width: 1
                  }
                  Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  TextField {
                    id: stateHex
                    Layout.preferredWidth: Style.space(110)
                    placeholderText: root.defaultStateColors[stateColorRow.modelData.key]
                    foreground: root.fg
                    text: (root.config.state_colors || {})[stateColorRow.modelData.key] || ""
                    onEditingFinished: root.setColorMap("state_colors", stateColorRow.modelData.key, text)
                  }
                  }
                  Swatches {
                    width: parent.width
                    onPicked: function(hex) { stateHex.text = hex; root.setColorMap("state_colors", stateColorRow.modelData.key, hex) }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "BAR & CYCLE"; foreground: root.fg; fontFamily: root.fontFamily }
              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                Button {
                  text: "Logos in bar: " + (root.showBarLogos ? "On" : "Off")
                  selected: root.showBarLogos
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.setConfig("bar_logos", !root.showBarLogos)
                }
                Button {
                  text: "League last in cycle: " + (root.cycleLeagues ? "On" : "Off")
                  selected: root.cycleLeagues
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.setConfig("league_in_cycle", !root.cycleLeagues)
                }
                Item { Layout.fillWidth: true }
              }
            }

            PanelSeparator { foreground: root.fg }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              Button {
                text: root.loading ? "Refreshing…" : "⟳ Refresh"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
              Text {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: (root.lastSaved !== "" ? "Saved " + root.lastSaved + " → " : "") + root.configPath
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                text: root.dirty ? "Save now" : "Saved"
                active: root.dirty
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: { root.saveConfig(); root.refresh() }
              }
            }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Score rows
  // -------------------------------------------------------------------------
  // -------------------------------------------------------------------------
  // Large "current game" card
  // -------------------------------------------------------------------------
  component Swatches: Flow {
    id: sw
    signal picked(string hex)
    spacing: Style.space(5)
    Repeater {
      model: root.swatchPalette
      delegate: Rectangle {
        id: chip
        required property string modelData
        width: Style.space(16)
        height: Style.space(16)
        radius: 4
        color: chip.modelData
        border.width: 1
        border.color: root.dim
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: sw.picked(chip.modelData)
        }
      }
    }
  }

  component TeamBlock: Column {
    id: tb
    property var side: null
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: Style.space(72)
      Image {
        anchors.centerIn: parent
        width: Style.space(72)
        height: Style.space(72)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        sourceSize.width: 160
        sourceSize.height: 160
        source: tb.side && tb.side.logo ? tb.side.logo : ""
      }
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: tb.side ? tb.side.abbr : ""
      color: root.teamColor(tb.side, root.fg)
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      font.bold: true
    }
    Item {
      width: parent.width
      height: Style.space(3)
      Rectangle {
        anchors.centerIn: parent
        width: Style.space(40)
        height: parent.height
        radius: height / 2
        color: root.teamColor(tb.side, "transparent")
      }
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: tb.side ? tb.side.name : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component BigGame: Rectangle {
    id: big
    property var game: null
    readonly property string cat: root.gameCategory(game)
    readonly property color catColor: root.stateColorFor(cat)

    width: parent ? parent.width : 0
    implicitHeight: bigCol.implicitHeight + Style.space(28)
    height: implicitHeight
    radius: Style.cornerRadius * 2
    color: Qt.rgba(big.catColor.r, big.catColor.g, big.catColor.b, 0.10)
    border.width: 2
    border.color: big.catColor

    MouseArea {
      anchors.fill: parent
      cursorShape: big.game && big.game.link ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (big.game && big.game.link) {
          Quickshell.execDetached(["xdg-open", big.game.link])
          root.close()
        }
      }
    }

    Column {
      id: bigCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(14)
      spacing: Style.space(12)

      RowLayout {
        width: parent.width
        Text {
          text: big.game ? big.game.league_label : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Item { Layout.fillWidth: true }
        Rectangle {
          id: badge
          radius: height / 2
          color: big.catColor
          implicitWidth: badgeText.implicitWidth + Style.space(16)
          implicitHeight: badgeText.implicitHeight + Style.space(6)
          Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.categoryLabel(big.cat)
            color: (badge.color.r * 0.299 + badge.color.g * 0.587 + badge.color.b * 0.114) > 0.55 ? "#111111" : "#FFFFFF"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        TeamBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.alignment: Qt.AlignTop
          side: big.game ? big.game.away : null
        }
        Column {
          Layout.preferredWidth: Style.space(130)
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: !big.game ? "" : (big.game.state === "pre" ? "@" : big.game.away.score + " – " + big.game.home.score)
            color: big.catColor
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.display * 1.6)
            font.bold: true
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: big.game ? root.gameDetail(big.game) : ""
            color: big.catColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
        TeamBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.alignment: Qt.AlignTop
          side: big.game ? big.game.home : null
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Score rows
  // -------------------------------------------------------------------------
  component GameRow: Rectangle {
    id: gameRow
    property var game
    width: parent ? parent.width : 0
    implicitHeight: rowContent.implicitHeight + Style.space(12)
    height: implicitHeight
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: gameRow.game && gameRow.game.link ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        if (gameRow.game && gameRow.game.link) {
          Quickshell.execDetached(["xdg-open", gameRow.game.link])
          root.close()
        }
      }
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: Style.space(3)
        Layout.preferredHeight: Style.space(28)
        radius: 2
        color: root.gameAccent(gameRow.game)
      }

      Text {
        Layout.preferredWidth: Style.space(52)
        text: gameRow.game ? gameRow.game.league_label : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Row {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Text {
          id: awayText
          text: (gameRow.game && gameRow.game.away ? gameRow.game.away.abbr : "") + "  " + (gameRow.game && gameRow.game.away ? gameRow.game.away.score : "")
          color: root.teamColor(gameRow.game ? gameRow.game.away : null, gameRow.game && gameRow.game.winner === "away" ? root.fg : Qt.darker(root.fg, 1.25))
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: gameRow.game ? gameRow.game.winner === "away" : false
        }
        Text {
          text: "@"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: (gameRow.game && gameRow.game.home ? gameRow.game.home.abbr : "") + "  " + (gameRow.game && gameRow.game.home ? gameRow.game.home.score : "")
          color: root.teamColor(gameRow.game ? gameRow.game.home : null, gameRow.game && gameRow.game.winner === "home" ? root.fg : Qt.darker(root.fg, 1.25))
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: gameRow.game ? gameRow.game.winner === "home" : false
        }
      }

      Text {
        text: gameRow.game ? root.gameDetail(gameRow.game) : ""
        color: root.gameAccent(gameRow.game)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ScoreSection: Column {
    id: section
    property string title: ""
    property var games: []
    property real rootWidth: 0
    width: rootWidth
    spacing: Style.space(6)
    visible: games.length > 0

    PanelSectionHeader { text: section.title; foreground: root.fg; fontFamily: root.fontFamily }

    Repeater {
      model: section.games.slice(0, 12)
      delegate: GameRow {
        required property var modelData
        width: section.width
        game: modelData
      }
    }
  }

  component LeaderSection: Column {
    id: leaderSection
    property string title: ""
    property var items: []
    property real rootWidth: 0
    width: rootWidth
    spacing: Style.space(6)
    visible: items.length > 0

    PanelSectionHeader { text: leaderSection.title; foreground: root.fg; fontFamily: root.fontFamily }

    Repeater {
      model: leaderSection.items
      delegate: Column {
        required property var modelData
        width: leaderSection.width
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: modelData.name + "  ·  " + (modelData.detail || modelData.state || "")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
        Repeater {
          model: (modelData.drivers || modelData.golfers || []).slice(0, 10)
          delegate: Text {
            required property var modelData
            width: parent.width
            text: modelData.pos + "  " + modelData.name + (modelData.car ? "  #" + modelData.car : "") + (modelData.strokes !== undefined ? "  (" + modelData.strokes + ")" : "") + (modelData.fav ? "  ★" : "")
            color: modelData.fav ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Processes and timers
  // -------------------------------------------------------------------------
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: false
    printErrors: false
    onLoaded: root.applyConfigText(text())
    onLoadFailed: root.saveConfig()
  }

  Process {
    id: ensureProc
    running: true
    command: ["python3", root.saveConfigScript, "--ensure"]
    onRunningChanged: if (!running) configFile.reload()
  }

  Process {
    id: fetchProc
    command: ["python3", root.fetchScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object") {
            root.scores = parsed
            if (parsed.error) root.statusText = "Fetch error: " + parsed.error
          }
        } catch (e) {
          root.statusText = "Could not read scores"
        }
        root.loading = false
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).trim().split("\n")
        var last = lines[lines.length - 1]
        if (last) root.statusText = "Fetch failed: " + last
      }
    }
    onRunningChanged: {
      if (!running) {
        root.loading = false
        if (root.refreshQueued) { root.refreshQueued = false; root.refresh() }
      }
    }
  }

  Process {
    id: saveProc
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.dirty = true; root.statusText = "Could not save settings (exit " + exitCode + ")" }
      else root.lastSaved = Qt.formatTime(new Date(), "h:mm:ss AP") + " · " + (root.config.teams || []).length + " teams"
    }
    onRunningChanged: {
      if (running) return
      if (root.savePending) { root.savePending = false; root.saveConfig() }
      else root.refresh()
    }
  }

  // Debounced autosave: favourites and colours persist without pressing Save.
  Timer {
    id: autosaveTimer
    interval: 600
    repeat: false
    onTriggered: root.saveConfig()
  }

  Process {
    id: barProc
    running: false
  }

  Timer {
    id: refreshTimer
    interval: Math.max(15, root.config.refresh_seconds || 60) * 1000
    running: root.bar !== null
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: rotateTimer
    interval: Math.max(2, root.config.rotate_seconds || 6) * 1000
    // Keep both the bar and opened scoreboard view rotating together.
    running: root.bar !== null && root.tiles.length > 1
    repeat: true
    onTriggered: root.rotateIndex = (root.safeIndex + 1) % Math.max(1, root.tiles.length)
  }

  onOpenedChanged: {
    if (opened) root.refresh()
    else {
      root.lastClosedAt = Date.now()
      root.lastClosedMode = root.mode
      if (dirty) root.saveConfig()
    }
  }
  Component.onCompleted: root.refresh()

  // First run after install: ask where the widget should live in the bar.
  Timer {
    id: firstRunTimer
    interval: 1500
    running: true
    onTriggered: {
      if (!root.config.positioned) {
        root.mode = "settings"
        root.open()
      }
    }
  }
}
