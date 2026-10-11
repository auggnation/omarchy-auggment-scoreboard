import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Auggment Scoreboard — bar item. This is the manifest entry point: it draws
// the scores in the bar, loads Panel.qml (data + popup) and forwards the panel
// lifecycle the shell uses for clicks and `omarchy-shell shell summon/hide`.
BarWidget {
  id: root
  moduleName: "io.github.auggnation.auggment-scoreboard"

  readonly property var panelItem: panelLoader.item

  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  // Everything drawn below comes from the loaded panel so the bar and the
  // popup always show the same tile.
  readonly property var barGame: panelItem ? panelItem.barGame : null
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color accentColor: panelItem ? panelItem.currentColor : fg
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool showLogos: panelItem ? panelItem.showBarLogos : true

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function barLabel() { return panelItem ? panelItem.barLabel() : "…" }
  function teamColor(side) { return panelItem ? panelItem.teamColor(side, fg) : fg }

  implicitWidth: Math.max(button.implicitWidth, barRow.implicitWidth + Style.space(12))
  implicitHeight: Math.max(button.implicitHeight, barRow.implicitHeight + Style.space(8))

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The stock bar button receives the bar's input, draws hover and anchors the
  // popup. Its own text stays empty; the logos/scores are drawn on top.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    horizontalMargin: 6
    verticalPadding: 4
    foreground: root.accentColor
    tooltipText: root.barLabel()
    onPressed: function(buttonCode) {
      if (!root.panelItem) return
      if (buttonCode === Qt.RightButton) root.panelItem.showMode("settings")
      else if (buttonCode === Qt.MiddleButton) root.panelItem.refresh()
      else root.panelItem.showMode("current")
    }
  }

  Row {
    id: barRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    // ---- game: [logo] AWAY 24–17 HOME [logo] ----
    Image {
      visible: root.showLogos && !!root.barGame && !!root.barGame.away.logo
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
      color: root.teamColor(root.barGame ? root.barGame.away : null)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      visible: !!root.barGame
      anchors.verticalCenter: parent.verticalCenter
      text: !root.barGame ? "" : (root.barGame.state === "pre" ? "@" : root.barGame.away.score + "–" + root.barGame.home.score)
      color: root.accentColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      visible: !!root.barGame
      anchors.verticalCenter: parent.verticalCenter
      text: root.barGame ? root.barGame.home.abbr : ""
      color: root.teamColor(root.barGame ? root.barGame.home : null)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Image {
      visible: root.showLogos && !!root.barGame && !!root.barGame.home.logo
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
      color: root.accentColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Scroll over the bar item to step through games without opening it.
  WheelHandler {
    onWheel: function(event) {
      if (!root.panelItem) return
      if (event.angleDelta.y > 0) root.panelItem.rotatePrev()
      else if (event.angleDelta.y < 0) root.panelItem.rotateNext()
    }
  }
}
