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
  property string mode: "scores"
  property int rotateIndex: 0
  property bool loading: false
  property bool dirty: false
  property string statusText: ""

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
      days_back: 1,
      days_ahead: 7,
      refresh_seconds: 60,
      rotate_seconds: 6,
      max_games: 40
    }
  }

  function setConfig(key, value) {
    var copy = {}
    for (var k in config) copy[k] = config[k]
    copy[key] = value
    config = copy
    dirty = true
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
  }

  function saveConfig() {
    if (saveProc.running) return
    saveProc.running = true
  }

  function refresh() {
    if (fetchProc.running) return
    loading = true
    statusText = ""
    fetchProc.running = true
  }

  // ---- tiles for the bar rotation ----------------------------------------

  readonly property var tiles: {
    var data = scores || {}
    var out = []
    var games = data.games || []
    for (var i = 0; i < games.length && out.length < 30; i++) if (games[i].is_fav) out.push(games[i])
    var races = data.races || []
    for (var j = 0; j < races.length && out.length < 30; j++) if (races[j].is_fav) out.push(races[j])
    var golf = data.golf || []
    for (var g = 0; g < golf.length && out.length < 30; g++) if (golf[g].is_fav) out.push(golf[g])
    return out
  }
  readonly property var currentTile: tiles.length > 0 ? tiles[rotateIndex % tiles.length] : null
  readonly property bool hasFavorites: {
    if ((config.teams || []).length > 0) return true
    if ((config.golf || []).length > 0) return true
    var racing = config.racing || {}
    for (var k in racing) if ((racing[k] || []).length > 0) return true
    return false
  }

  function stateColor(state) {
    if (state === "in") return Color.accent
    if (state === "post") return Color.muted
    return fg
  }

  function shortTime(s) {
    var t = String(s || "")
    var sp = t.indexOf(" ")
    return sp >= 0 ? t.substring(sp + 1) : t
  }

  function barLabel() {
    var t = currentTile
    if (!t) return loading ? "…" : "—"
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
  readonly property var favGames: (scores.games || []).filter(function(g) { return g.is_fav })
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
    var leagues = racingLeagues()
    for (var i = 0; i < leagues.length; i++) dict[leagues[i]] = names
    setConfig("racing", dict)
  }
  function applyGolf(text) {
    var names = String(text || "").split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
    setConfig("golf", names)
  }

  // -------------------------------------------------------------------------
  // Bar button
  // -------------------------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel()
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    horizontalMargin: 6
    verticalPadding: 4
    foreground: root.stateColor(root.currentTile && root.currentTile.kind === "game" ? root.currentTile.state : "")
    tooltipText: "Auggment Scoreboard"
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.mode = "settings"; root.open() }
      else if (b === Qt.MiddleButton) root.refresh()
      else { root.mode = "scores"; root.toggle() }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function scores(): void { root.mode = "scores"; root.open() }
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.mode = root.mode === "scores" ? "settings" : "scores"
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
            spacing: Style.space(8)

            Button {
              text: "Scores"
              selected: root.mode === "scores"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.mode = "scores"
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
              text: root.loading ? "Refreshing…" : "Refresh"
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
            ScoreSection { title: "LIVE"; games: root.liveGames; rootWidth: column.width }
            ScoreSection { title: "UPCOMING"; games: root.preGames; rootWidth: column.width }
            ScoreSection { title: "FINALS"; games: root.postGames; rootWidth: column.width }
            LeaderSection { title: "RACING"; items: (root.scores.races || []); rootWidth: column.width }
            LeaderSection { title: "GOLF"; items: (root.scores.golf || []); rootWidth: column.width }
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

              PanelSectionHeader { text: "FAVORITE TEAMS"; foreground: root.fg; fontFamily: root.fontFamily }
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
                text: root.racingDriversText()
                onEditingFinished: root.applyRacing(text)
              }
              TextField {
                id: golfField
                width: parent.width
                placeholderText: "Golf players (e.g. Scheffler)"
                foreground: root.fg
                text: (root.config.golf || []).join(", ")
                onEditingFinished: root.applyGolf(text)
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: (root.config.teams || []).length > 0

              PanelSectionHeader { text: "TEAM COLORS"; foreground: root.fg; fontFamily: root.fontFamily }
              Text {
                width: parent.width
                text: "Override a team's bar color. Leave blank to use the team's own color."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.config.teams || []
                delegate: RowLayout {
                  required property string modelData
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
                    Layout.preferredWidth: Style.space(110)
                    placeholderText: "#RRGGBB"
                    foreground: root.fg
                    text: (root.config.team_colors || {})[modelData] || ""
                    onEditingFinished: {
                      var colors = {}
                      var existing = root.config.team_colors || {}
                      for (var k in existing) colors[k] = existing[k]
                      var v = String(text || "").trim()
                      if (v === "") delete colors[modelData]
                      else colors[modelData] = v.startsWith("#") ? v : ("#" + v)
                      root.setConfig("team_colors", colors)
                    }
                  }
                }
              }
            }

            PanelSeparator { foreground: root.fg }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              Item { Layout.fillWidth: true }
              Button {
                text: root.dirty ? "Save" : "Saved"
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
        color: root.stateColor(gameRow.game ? gameRow.game.state : "")
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
          color: gameRow.game && gameRow.game.winner === "away" ? root.fg : Qt.darker(root.fg, 1.25)
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
          color: gameRow.game && gameRow.game.winner === "home" ? root.fg : Qt.darker(root.fg, 1.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: gameRow.game ? gameRow.game.winner === "home" : false
        }
      }

      Text {
        text: gameRow.game ? root.gameDetail(gameRow.game) : ""
        color: root.stateColor(gameRow.game ? gameRow.game.state : "")
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
    onLoadFailed: { root.config = root.defaultConfig(); root.saveConfig() }
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
          if (parsed && typeof parsed === "object") root.scores = parsed
        } catch (e) {
          root.statusText = "Could not read scores"
        }
        root.loading = false
      }
    }
    onRunningChanged: if (!running) root.loading = false
  }

  Process {
    id: saveProc
    stdinEnabled: true
    command: ["python3", root.saveConfigScript]
    onStarted: {
      write(JSON.stringify(root.config))
      root.dirty = false
    }
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
    running: root.bar !== null && root.tiles.length > 1
    repeat: true
    onTriggered: root.rotateIndex = (root.rotateIndex + 1) % Math.max(1, root.tiles.length)
  }

  onOpenedChanged: if (opened) root.refresh()
  Component.onCompleted: root.refresh()
}
