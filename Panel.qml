import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.deandesign.launch-schedule"
  ipcTarget: "io.github.deandesign.launch-schedule"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Lifecycle (mirrors omarchy.weather) --------------------------------

  function open() { openFromHotkey() }

  function openFromHotkey() {
    root.controller.show()
    root.nowMs = Date.now()
    root.refresh(false)
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.playing = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  // ---- Data ---------------------------------------------------------------

  readonly property string fetchScript: decodeURIComponent(Qt.resolvedUrl("bin/fetch").toString().replace(/^file:\/\//, ""))

  property var launches: []
  // What the list shows: upcoming launches plus finished ones still worth
  // watching (see Model.isListed). Reassigned only when the set of ids
  // changes, so the rows aren't rebuilt on every clock tick.
  property var shownLaunches: []
  readonly property real recentHours: Math.max(0, Number(setting("recentHours", 24)) || 0)

  function refreshShown() {
    var now = Date.now()
    var next = launches.filter(function(l) { return Model.isListed(l, now, root.recentHours) })
    var same = next.length === shownLaunches.length
    for (var i = 0; same && i < next.length; i++) same = next[i] === shownLaunches[i]
    if (!same) {
      shownLaunches = next
      selectedIndex = Math.max(0, Math.min(selectedIndex, next.length - 1))
    }
  }

  onLaunchesChanged: refreshShown()
  onRecentHoursChanged: refreshShown()

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refreshShown()
  }
  property var stations: ({})
  property var tle: ({})
  property real lastUpdated: 0
  property string error: ""
  property real nowMs: Date.now()
  readonly property bool loading: launchesProc.running || stationsProc.running || tleProc.running

  function refresh(force) {
    var flag = force ? "force" : ""
    if (!launchesProc.running) { launchesProc.command = ["bash", fetchScript, "launches", flag]; launchesProc.running = true }
    if (!stationsProc.running) { stationsProc.command = ["bash", fetchScript, "stations", flag]; stationsProc.running = true }
    if (!tleProc.running) { tleProc.command = ["bash", fetchScript, "tle", flag]; tleProc.running = true }
  }

  Process {
    id: launchesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseLaunches(text)
        if (parsed) {
          root.launches = parsed
          root.lastUpdated = Date.now()
          root.error = ""
          if (root.detailLaunch) {
            for (var i = 0; i < parsed.length; i++)
              if (parsed[i].id === root.detailLaunch.id) { root.detailLaunch = parsed[i]; break }
          }
        } else if (root.launches.length === 0) {
          root.error = "Couldn't reach Launch Library. Retrying shortly."
        }
      }
    }
  }

  Process {
    id: stationsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseStations(text)
        if (parsed) root.stations = parsed
      }
    }
  }

  Process {
    id: tleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseTle(text)
        if (parsed) root.tle = parsed
      }
    }
  }

  // The fetch script decides whether its cache is stale, so polling often is
  // cheap and still respects the Launch Library rate limit.
  Timer {
    interval: 10 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // ---- Bar summary --------------------------------------------------------

  readonly property var nextLaunch: {
    for (var i = 0; i < launches.length; i++) {
      var l = launches[i]
      if (l.net > nowMs && l.kind !== "success" && l.kind !== "fail") return l
    }
    return null
  }
  readonly property bool anyLive: {
    for (var i = 0; i < launches.length; i++) if (launches[i].webcastLive) return true
    return false
  }
  // A launch is "happening" while its webcast is live, while it's in flight,
  // or from 15 minutes before to 20 minutes after liftoff.
  readonly property bool launchActive: {
    for (var i = 0; i < launches.length; i++) {
      var l = launches[i]
      if (l.webcastLive || l.status === "In Flight") return true
      if (nowMs > l.net - 15 * 60000 && nowMs < l.net + 20 * 60000 && l.kind !== "fail") return true
    }
    return false
  }
  readonly property string barCountdown: {
    var hours = Number(setting("countdownHours", 48))
    if (!setting("showCountdown", true) || !nextLaunch) return ""
    if (nextLaunch.net - nowMs > hours * 3600000) return ""
    return "T-" + Model.shortCountdown(nextLaunch.net, nowMs)
  }
  readonly property string tooltip: nextLaunch
    ? "Next: " + nextLaunch.missionName + " (" + Model.countdown(nextLaunch.net, nowMs) + ")"
    : "Launch schedule"

  // ---- Navigation state ---------------------------------------------------

  property string tab: "launches"      // launches | iss | css
  property var detailLaunch: null
  property int selectedIndex: 0

  function openDetail(launch) {
    if (!launch) return
    detailLaunch = launch
    var sinceT0 = (nowMs - launch.net) / 1000
    simLive = sinceT0 > 0 && sinceT0 < 6 * 3600
    simOffset = simLive ? sinceT0 : 0
    playing = false
    detailGlobe.zoom = 1
    detailGlobe.mode = "globe"
    detailGlobe.centerOn(launch.padLat + 8, launch.padLon + 25)
    scroll.contentY = 0
    // Already flying: centre on where the model puts the vehicle now.
    if (simLive) Qt.callLater(function() { if (root.vehicleAt) detailGlobe.centerOn(root.vehicleAt.lat, root.vehicleAt.lon) })
  }

  function back() {
    detailLaunch = null
    playing = false
    scroll.contentY = 0
  }

  function setTab(name) {
    back()
    tab = name
    if (name !== "launches") {
      follow = true
      stationGlobe.zoom = 1
    }
  }

  function cycleTab(direction) {
    var tabs = ["launches", "iss", "css"]
    setTab(tabs[(tabs.indexOf(tab) + direction + tabs.length) % tabs.length])
  }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }

  function scrollBy(dy) {
    var max = Math.max(0, scroll.contentHeight - scroll.height)
    scroll.contentY = Math.max(0, Math.min(max, scroll.contentY + dy))
  }

  function scrollToItem(item) {
    if (!item) return
    var y = item.mapToItem(content, 0, 0).y
    if (y < scroll.contentY) scroll.contentY = y
    else if (y + item.height > scroll.contentY + scroll.height) scroll.contentY = y + item.height - scroll.height
  }

  // ---- Simulation clock for the trajectory view ---------------------------

  property real simOffset: 0          // seconds after T-0
  property bool simLive: false        // track wall clock
  property bool playing: false

  readonly property real simTime: detailLaunch ? detailLaunch.net + (simLive ? nowMs - detailLaunch.net : simOffset * 1000) : nowMs
  readonly property real simSeconds: detailLaunch ? (simTime - detailLaunch.net) / 1000 : 0

  function stepSim(seconds) {
    if (!detailLaunch) return
    simOffset = Math.max(-1800, Math.min(4 * 3600, simSeconds + seconds))
    simLive = false
  }

  function resetSim(toNow) {
    if (!detailLaunch) return
    playing = false
    if (toNow) { simLive = true } else { simLive = false; simOffset = 0 }
  }

  Timer {
    interval: 100
    running: root.playing && root.opened
    repeat: true
    onTriggered: {
      root.stepSim(15)
      if (root.simSeconds >= 4 * 3600) root.playing = false
    }
  }

  function fmtClock(seconds) {
    var s = Math.abs(Math.round(seconds))
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
    function p(n) { return n < 10 ? "0" + n : String(n) }
    return (seconds < 0 ? "T-" : "T+") + p(h) + ":" + p(m) + ":" + p(x)
  }

  // ---- Colours ------------------------------------------------------------

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  // Secondary text blends toward the popup background, so it reads as muted
  // on light and dark themes alike (Qt.darker only works on light-on-dark).
  readonly property color dim: blend(fg, Color.popups.background, 0.62)
  readonly property color faint: blend(fg, Color.popups.background, 0.42)

  function blend(a, b, t) {
    return Qt.rgba(a.r * t + b.r * (1 - t), a.g * t + b.g * (1 - t), a.b * t + b.b * (1 - t), 1)
  }

  function hex(c) {
    function h(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }

  function statusColor(kind) {
    switch (kind) {
      case "go": case "flight": return Color.accent
      case "hold": case "fail": return Color.urgent
      case "success": return root.fg
      default: return root.dim
    }
  }

  readonly property string stationHex: hex(Color.accent)
  readonly property string vehicleHex: hex(Color.urgent)
  readonly property string vehicleOrbitHex: hex(blend(Color.urgent, Color.popups.background, 0.6))
  readonly property string markerHex: hex(root.fg)

  // ---- Launch trajectory model --------------------------------------------

  readonly property var detailOrbit: detailLaunch ? Model.targetOrbit(detailLaunch, tle) : null
  readonly property var detailTrack: detailLaunch && !isNaN(detailLaunch.padLat) ? Model.launchTrack(detailLaunch, detailOrbit, 9000, 20) : null
  readonly property var detailStationEl: detailLaunch && detailLaunch.station ? (tle[detailLaunch.station.norad] || null) : null
  readonly property var vehicleAt: detailTrack ? Model.vehiclePosition(detailLaunch, detailTrack.geometry, Math.min(simSeconds, detailOrbit.suborbital ? 600 : 1e9), detailOrbit.suborbital) : null
  readonly property var stationAtSim: detailStationEl ? Model.stationPosition(detailStationEl, simTime) : null

  readonly property var detailLayers: {
    var layers = []
    if (detailStationEl) {
      var period = 1440 / detailStationEl.meanMotion * 60000
      layers.push({ points: Model.stationTrack(detailStationEl, simTime - period * 0.4, simTime + period * 1.1, 20), ch: "·", color: stationHex })
    }
    if (detailTrack) {
      var pts = detailTrack.points
      layers.push({ points: pts.slice(detailTrack.insertion), ch: "+", color: vehicleOrbitHex })
      layers.push({ points: pts.slice(0, detailTrack.insertion + 1), ch: "*", color: vehicleHex })
    }
    return layers
  }

  readonly property var detailMarkers: {
    if (!detailLaunch || isNaN(detailLaunch.padLat)) return []
    var m = [{ lat: detailLaunch.padLat, lon: detailLaunch.padLon, ch: "P", color: markerHex }]
    if (stationAtSim) m.push({ lat: stationAtSim.lat, lon: stationAtSim.lon, ch: "@", color: stationHex })
    if (vehicleAt && simSeconds > 0) m.push({ lat: vehicleAt.lat, lon: vehicleAt.lon, ch: "R", color: vehicleHex })
    return m
  }

  // ---- Station view model -------------------------------------------------

  property bool follow: true
  readonly property var tabStation: tab === "launches" ? null : (stations[tab] || null)
  readonly property int tabNorad: tab === "iss" ? 25544 : (tab === "css" ? 48274 : 0)
  readonly property var tabEl: tabNorad ? (tle[tabNorad] || null) : null
  readonly property var tabPos: tabEl ? Model.stationPosition(tabEl, nowMs) : null
  readonly property var tabLayers: {
    if (!tabEl) return []
    var period = 1440 / tabEl.meanMotion * 60000
    var minute = Math.floor(nowMs / 60000) * 60000   // only recompute the track once a minute
    return [
      { points: Model.stationTrack(tabEl, minute - period * 0.35, minute, 20), ch: ":", color: hex(blend(Color.accent, Color.popups.background, 0.5)) },
      { points: Model.stationTrack(tabEl, minute, minute + period * 1.4, 20), ch: "·", color: stationHex }
    ]
  }
  readonly property var tabUpcoming: {
    var out = []
    for (var i = 0; i < shownLaunches.length; i++)
      if (shownLaunches[i].station && shownLaunches[i].station.key === tab) out.push(shownLaunches[i])
    return out
  }

  onTabPosChanged: if (follow && tabPos && tab !== "launches") stationGlobe.centerOn(tabPos.lat * 0.6, tabPos.lon)

  // ---- Keyboard -----------------------------------------------------------

  function activeGlobe() {
    if (detailLaunch) return detailGlobe
    if (tab !== "launches") return stationGlobe
    return null
  }

  function moveCursor(dx, dy) {
    var globe = activeGlobe()
    if (globe) {
      if (dx !== 0) globe.spin(dx * 15, 0)
      if (dy !== 0) scrollBy(dy * Style.space(60))
      return
    }
    if (dx !== 0) { cycleTab(dx); return }
    if (shownLaunches.length === 0) return
    selectedIndex = Math.max(0, Math.min(shownLaunches.length - 1, selectedIndex + dy))
    scrollToItem(launchRepeater.itemAt(selectedIndex))
  }

  function activate() {
    if (detailLaunch) { playing = !playing; if (playing && simSeconds >= 4 * 3600) simOffset = 0; return }
    if (tab === "launches") openDetail(shownLaunches[selectedIndex])
  }

  function handleText(t) {
    var globe = activeGlobe()
    switch (t) {
      case "r": refresh(true); return
      case "1": setTab("launches"); return
      case "2": setTab("iss"); return
      case "3": setTab("css"); return
      case "b": case "\b": if (detailLaunch) back(); return
      case "o":
        if (detailLaunch && detailLaunch.vids.length > 0) openUrl(detailLaunch.vids[0].url)
        return
    }
    if (!globe) return
    switch (t) {
      case "m": globe.mode = globe.mode === "map" ? "globe" : "map"; return
      case "+": case "=": globe.setZoom(globe.zoom * 1.25); return
      case "-": case "_": globe.setZoom(globe.zoom / 1.25); return
      case "w": globe.spin(0, 10); return
      case "s": globe.spin(0, -10); return
      case "f": if (!detailLaunch) follow = true; return
      case "[": stepSim(-60); return
      case "]": stepSim(60); return
      case "{": stepSim(-600); return
      case "}": stepSim(600); return
      case "0": resetSim(false); return
      case "n": resetSim(true); return
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(true) }
  }

  // ---- UI -----------------------------------------------------------------

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component Caption: Label {
    color: root.dim
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  component Section: Column {
    property string title: ""
    width: parent ? parent.width : 0
    spacing: Style.space(6)
    PanelSectionHeader {
      text: title
      foreground: root.fg
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }

  component Chip: Rectangle {
    property alias text: chipLabel.text
    property color tint: root.fg
    implicitWidth: chipLabel.implicitWidth + Style.space(10)
    implicitHeight: chipLabel.implicitHeight + Style.space(4)
    radius: Math.min(4, Style.cornerRadius)
    color: Util.alpha(tint, 0.14)
    border.width: 1
    border.color: Util.alpha(tint, 0.45)
    Label {
      id: chipLabel
      anchors.centerIn: parent
      color: parent.tint
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component LinkRow: Rectangle {
    id: link
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string url: ""
    property bool live: false
    width: parent ? parent.width : 0
    height: linkCol.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: linkMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: link.live ? "●" : link.icon
        color: link.live ? Color.urgent : root.dim
        font.pixelSize: Style.font.title
        width: Style.space(16)
      }
      Column {
        id: linkCol
        width: parent.width - Style.space(26)
        spacing: Style.space(1)
        Label {
          width: parent.width
          text: (link.live ? "LIVE · " : "") + link.title
          color: linkMouse.containsMouse ? Style.hoverStateColor(root.fg, Color.accent) : root.fg
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: link.subtitle
          color: root.dim
          font.pixelSize: Style.font.caption
        }
      }
    }

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openUrl(link.url)
    }
  }

  component KeyValue: Column {
    property string key: ""
    property string value: ""
    visible: value !== ""
    spacing: Style.space(2)
    Caption { text: key.toUpperCase() }
    Label { text: value; width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone }
  }

  component CrewRow: Row {
    property var person: null
    width: parent ? parent.width : 0
    spacing: Style.space(10)
    Label { width: parent.width * 0.42; text: person ? person.name : "" }
    Label { width: parent.width * 0.34; text: person ? person.role : ""; color: root.dim }
    Label { width: parent.width * 0.24 - Style.space(20); text: person ? person.agency : ""; color: root.dim; horizontalAlignment: Text.AlignRight }
  }

  component TextButton: Rectangle {
    id: tb
    property string label: ""
    property bool selected: false
    signal clicked()
    implicitWidth: tbText.implicitWidth + Style.space(14)
    implicitHeight: tbText.implicitHeight + Style.space(8)
    radius: Math.min(4, Style.cornerRadius)
    color: selected ? Style.selectedFillFor(root.fg, Color.accent) : (tbMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : Style.normalFillFor(root.fg, Color.accent))
    border.width: 1
    border.color: selected ? Style.selectedBorderFor(root.fg, Color.accent) : Style.normalBorderFor(root.fg, Color.accent)
    Label {
      id: tbText
      anchors.centerIn: parent
      text: tb.label
      color: tb.selected ? Style.selectedStateColor(root.fg, Color.accent) : root.fg
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: tbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tb.clicked()
    }
  }

  component Legend: Row {
    property string glyph: ""
    property color tint: root.fg
    property string label: ""
    spacing: Style.space(4)
    Label { text: glyph; color: tint; font.bold: true; font.pixelSize: Style.font.bodySmall }
    Label { text: label; color: root.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(780)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.detailLaunch ? root.back() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleText(t) }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height && !detailGlobe.dragging && !stationGlobe.dragging

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(12)

          // ---- Header: tabs (or back) + refresh ----------------------------
          Item {
            width: parent.width
            height: Math.max(tabsRow.implicitHeight, refreshButton.height)

            Row {
              id: tabsRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              TextButton {
                visible: root.detailLaunch !== null
                label: "‹ Back"
                onClicked: root.back()
              }
              Repeater {
                model: root.detailLaunch ? [] : [
                  { key: "launches", label: "󱓞  Launches" },
                  { key: "iss", label: "ISS" },
                  { key: "css", label: "Tiangong" }
                ]
                TextButton {
                  required property var modelData
                  label: modelData.label
                  selected: root.tab === modelData.key
                  onClicked: root.setTab(modelData.key)
                }
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Caption {
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "UPDATING…" : (root.lastUpdated > 0 ? "UPDATED " + Qt.formatTime(new Date(root.lastUpdated), "HH:mm") : "")
              }
              PanelActionButton {
                id: refreshButton
                iconText: "󰑐"
                tooltipText: "Refresh (r)"
                foreground: root.fg
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onClicked: root.refresh(true)
              }
            }
          }

          Label {
            visible: root.error !== ""
            width: parent.width
            text: root.error
            color: Color.urgent
            wrapMode: Text.Wrap
          }

          // ================= Launch list =================
          Column {
            visible: root.tab === "launches" && !root.detailLaunch
            width: parent.width
            spacing: Style.space(2)

            Label {
              visible: root.shownLaunches.length === 0 && root.error === ""
              text: root.launches.length === 0 ? "Fetching launch schedule…" : "No upcoming launches right now."
              color: root.dim
              font.italic: true
            }

            Repeater {
              id: launchRepeater
              model: root.shownLaunches

              Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: index === root.selectedIndex
                width: parent.width
                height: rowCol.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: current || rowMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                border.width: current ? 1 : 0
                border.color: Style.hoverBorderFor(root.fg, Color.accent)

                Column {
                  id: rowCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Item {
                    width: parent.width
                    height: Math.max(statusChip.implicitHeight, missionLabel.implicitHeight)
                    Row {
                      id: leftTop
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)
                      width: parent.width - countdownLabel.implicitWidth - Style.space(12)
                      Chip {
                        id: statusChip
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.status.toUpperCase()
                        tint: root.statusColor(row.modelData.kind)
                      }
                      Chip {
                        visible: row.modelData.webcastLive
                        anchors.verticalCenter: parent.verticalCenter
                        text: "● LIVE"
                        tint: Color.urgent
                      }
                      Label {
                        id: missionLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, leftTop.width - statusChip.width - Style.space(70))
                        text: row.modelData.missionName
                        font.bold: true
                        color: row.current ? Style.hoverStateColor(root.fg, Color.accent) : root.fg
                      }
                      Label {
                        visible: row.modelData.crew.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰀄 " + row.modelData.crew.length
                        color: Color.accent
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                    Label {
                      id: countdownLabel
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.countdown(row.modelData.net, root.nowMs)
                      color: row.modelData.net > root.nowMs ? root.fg : root.dim
                      font.bold: row.modelData.net > root.nowMs && row.modelData.net - root.nowMs < 86400000
                    }
                  }

                  Item {
                    width: parent.width
                    height: subLabel.implicitHeight
                    Label {
                      id: subLabel
                      anchors.left: parent.left
                      width: parent.width - whenLabel.implicitWidth - Style.space(12)
                      text: row.modelData.rocketName + " · " + row.modelData.providerAbbrev + " · " + row.modelData.location
                        + (row.modelData.station ? "  → " + row.modelData.station.short : "")
                      color: root.dim
                      font.pixelSize: Style.font.bodySmall
                    }
                    Label {
                      id: whenLabel
                      anchors.right: parent.right
                      text: Qt.formatDateTime(new Date(row.modelData.net), "ddd d MMM  HH:mm")
                        + (row.modelData.netPrecision && row.modelData.netPrecision !== "Second" && row.modelData.netPrecision !== "Minute" ? " (" + row.modelData.netPrecision + ")" : "")
                      color: root.dim
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = row.index
                  onClicked: root.openDetail(row.modelData)
                }
              }
            }

            Caption {
              visible: root.shownLaunches.length > 0
              topPadding: Style.space(6)
              text: "↑↓ SELECT · ⏎ DETAILS · ←→ TABS · R REFRESH  —  DATA: THE SPACE DEVS LAUNCH LIBRARY"
              font.pixelSize: Style.font.caption - 1
            }
          }

          // ================= Launch detail =================
          Column {
            id: detail
            visible: root.detailLaunch !== null
            width: parent.width
            spacing: Style.space(14)
            readonly property var l: root.detailLaunch || ({ vids: [], info: [], crew: [], timeline: [] })

            // Hero
            Column {
              width: parent.width
              spacing: Style.space(4)
              Label {
                width: parent.width
                text: detail.l.missionName || ""
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Label {
                width: parent.width
                text: (detail.l.rocketName || "") + " · " + (detail.l.provider || "")
                color: root.dim
              }
              Row {
                spacing: Style.space(10)
                topPadding: Style.space(6)
                Label {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.countdown(detail.l.net, root.nowMs)
                  font.pixelSize: Style.font.display
                  font.bold: true
                }
                Chip {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (detail.l.statusName || "").toUpperCase()
                  tint: root.statusColor(detail.l.kind)
                }
                Chip {
                  visible: detail.l.webcastLive === true
                  anchors.verticalCenter: parent.verticalCenter
                  text: "● WEBCAST LIVE"
                  tint: Color.urgent
                }
              }
              Label {
                width: parent.width
                text: isNaN(detail.l.net) ? "" : "NET " + Qt.formatDateTime(new Date(detail.l.net), "dddd d MMMM yyyy · HH:mm:ss")
                  + (detail.l.netPrecision ? "  (precision: " + detail.l.netPrecision.toLowerCase() + ")" : "")
                color: root.dim
                font.pixelSize: Style.font.bodySmall
              }
              Label {
                visible: !isNaN(detail.l.windowStart) && !isNaN(detail.l.windowEnd) && detail.l.windowEnd > detail.l.windowStart
                width: parent.width
                text: "Window " + Qt.formatTime(new Date(detail.l.windowStart), "HH:mm") + " – " + Qt.formatTime(new Date(detail.l.windowEnd), "HH:mm")
                  + "  (" + Model.formatSeconds((detail.l.windowEnd - detail.l.windowStart) / 1000) + ")"
                color: root.dim
                font.pixelSize: Style.font.bodySmall
              }
              Label {
                visible: detail.l.probability >= 0 || detail.l.weatherConcerns !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: (detail.l.probability >= 0 ? "Weather go: " + detail.l.probability + "%" : "")
                  + (detail.l.weatherConcerns ? (detail.l.probability >= 0 ? " · " : "") + detail.l.weatherConcerns : "")
                color: root.dim
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Streams
            Section {
              title: "WATCH"
              Repeater {
                model: detail.l.vids
                LinkRow {
                  required property var modelData
                  icon: "󰗃"
                  live: modelData.live
                  title: modelData.title
                  subtitle: modelData.publisher + (modelData.official ? " · official" : "")
                    + (!isNaN(modelData.start) && !modelData.live ? " · starts " + Qt.formatDateTime(new Date(modelData.start), "ddd HH:mm") : "")
                  url: modelData.url
                }
              }
              Label {
                visible: detail.l.vids.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                text: "No streams posted yet. They're usually added a day or two before launch."
                color: root.dim
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
              LinkRow {
                visible: detail.l.flightclub !== "" && detail.l.flightclub !== undefined
                icon: "󰑞"
                title: "Flight Club: full ascent trajectory simulation"
                subtitle: "Live telemetry overlay during launch"
                url: detail.l.flightclub || ""
              }
              Repeater {
                model: detail.l.info
                LinkRow {
                  required property var modelData
                  icon: "󰖟"
                  title: modelData.title
                  url: modelData.url
                }
              }
            }

            // Trajectory
            Section {
              title: "TRAJECTORY"

              Row {
                spacing: Style.space(6)
                TextButton { label: "Globe"; selected: detailGlobe.mode === "globe"; onClicked: detailGlobe.mode = "globe" }
                TextButton { label: "Map"; selected: detailGlobe.mode === "map"; onClicked: detailGlobe.mode = "map" }
                Item { width: Style.space(10); height: 1 }
                TextButton { label: "Pad"; onClicked: detailGlobe.centerOn(detail.l.padLat, detail.l.padLon) }
                TextButton { visible: root.vehicleAt !== null && root.simSeconds > 0; label: "Vehicle"; onClicked: detailGlobe.centerOn(root.vehicleAt.lat, root.vehicleAt.lon) }
                TextButton { visible: root.stationAtSim !== null; label: detail.l.station ? detail.l.station.short : ""; onClicked: detailGlobe.centerOn(root.stationAtSim.lat, root.stationAtSim.lon) }
                TextButton { label: "−"; onClicked: detailGlobe.setZoom(detailGlobe.zoom / 1.25) }
                TextButton { label: "+"; onClicked: detailGlobe.setZoom(detailGlobe.zoom * 1.25) }
              }

              Globe {
                id: detailGlobe
                width: parent.width
                bar: root.bar
                time: root.simTime
                layers: root.detailLayers
                markers: root.detailMarkers
              }

              Flow {
                width: parent.width
                spacing: Style.space(14)
                Legend { glyph: "P"; tint: root.fg; label: "pad" }
                Legend { glyph: "*"; tint: Color.urgent; label: "ascent" }
                Legend { glyph: "+"; tint: root.vehicleOrbitHex; label: "orbit" }
                Legend { visible: root.simSeconds > 0; glyph: "R"; tint: Color.urgent; label: "vehicle" }
                Legend { visible: root.detailStationEl !== null; glyph: "@ ·"; tint: Color.accent; label: detail.l.station ? detail.l.station.short + " & track" : "" }
                Legend { glyph: "#/%"; tint: root.dim; label: "land day/night" }
              }

              // Sim clock
              Row {
                spacing: Style.space(6)
                Label {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.fmtClock(root.simSeconds)
                  font.bold: true
                  width: Style.space(96)
                }
                TextButton { label: "−10m"; onClicked: root.stepSim(-600) }
                TextButton { label: "−1m"; onClicked: root.stepSim(-60) }
                TextButton { label: root.playing ? "❚❚" : "▶"; selected: root.playing; onClicked: root.activate() }
                TextButton { label: "+1m"; onClicked: root.stepSim(60) }
                TextButton { label: "+10m"; onClicked: root.stepSim(600) }
                TextButton { label: "T-0"; onClicked: root.resetSim(false) }
                TextButton { label: "Now"; selected: root.simLive; onClicked: root.resetSim(true) }
              }

              Grid {
                width: parent.width
                columns: 3
                columnSpacing: Style.space(16)
                rowSpacing: Style.space(8)
                topPadding: Style.space(4)
                readonly property real cellW: (width - columnSpacing * 2) / 3
                KeyValue {
                  width: parent.cellW
                  key: "Launch azimuth"
                  value: root.detailOrbit && !isNaN(detail.l.padLat) ? Math.round(Model.launchAzimuth(detail.l, root.detailOrbit)) + "° (" + Model.compass(Model.launchAzimuth(detail.l, root.detailOrbit)) + ")" : ""
                }
                KeyValue {
                  width: parent.cellW
                  key: "Inclination"
                  value: root.detailOrbit ? root.detailOrbit.inc.toFixed(1) + "°" + (root.detailOrbit.estimated ? " (est.)" : "") : ""
                }
                KeyValue {
                  width: parent.cellW
                  key: "Orbit period"
                  value: root.detailTrack && !root.detailOrbit.suborbital ? root.detailTrack.period.toFixed(1) + " min @ ~" + Math.round(root.detailOrbit.alt) + " km" : ""
                }
                KeyValue {
                  width: parent.cellW
                  key: "Vehicle (model)"
                  value: root.vehicleAt && root.simSeconds > 0 ? Model.formatLatLon(root.vehicleAt) : "On the pad"
                }
                KeyValue {
                  width: parent.cellW
                  key: detail.l.station ? detail.l.station.short + " now at" : ""
                  value: root.stationAtSim ? Model.formatLatLon(root.stationAtSim) + " · " + Math.round(root.stationAtSim.alt) + " km" : ""
                }
                KeyValue {
                  width: parent.cellW
                  key: "Separation (model)"
                  value: root.stationAtSim && root.vehicleAt ? Math.round(Model.greatCircleKm(root.vehicleAt, root.stationAtSim)).toLocaleString() + " km ground" : ""
                }
              }
              Label {
                width: parent.width
                wrapMode: Text.Wrap
                color: root.faint
                font.pixelSize: Style.font.caption
                text: (root.detailOrbit ? root.detailOrbit.note + ". " : "")
                  + "Ground track is a simplified model (circular orbit, eased ascent, no phasing burns); it isn't flight data. Drag to spin, scroll to zoom, M toggles map, [ ] steps time, space plays."
              }
            }

            // Mission
            Section {
              title: "MISSION"
              Grid {
                width: parent.width
                columns: 2
                columnSpacing: Style.space(20)
                rowSpacing: Style.space(8)
                readonly property real cellW: (width - columnSpacing) / 2
                KeyValue { width: parent.cellW; key: "Destination"; value: detail.l.destination || "" }
                KeyValue { width: parent.cellW; key: "Orbit"; value: detail.l.orbitName ? detail.l.orbitName + (detail.l.orbitAbbrev ? " (" + detail.l.orbitAbbrev + ")" : "") : "" }
                KeyValue { width: parent.cellW; key: "Spacecraft"; value: detail.l.spacecraft ? detail.l.spacecraft + (detail.l.spacecraftType ? " · " + detail.l.spacecraftType : "") : "" }
                KeyValue { width: parent.cellW; key: "Mission length"; value: detail.l.missionDuration || "" }
                KeyValue { width: parent.cellW; key: "Mission type"; value: detail.l.missionType || "" }
                KeyValue { width: parent.cellW; key: "Pad"; value: detail.l.padName ? detail.l.padName + " · " + detail.l.location : "" }
              }
              Label {
                visible: text !== ""
                width: parent.width
                text: detail.l.description || ""
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                color: root.dim
                lineHeight: 1.15
              }
            }

            // Crew
            Section {
              visible: detail.l.crew.length > 0
              title: "CREW · " + detail.l.crew.length
              Repeater {
                model: detail.l.crew
                CrewRow { required property var modelData; person: modelData }
              }
            }

            // Destination station crew
            Section {
              readonly property var st: detail.l.station ? root.stations[detail.l.station.key] : null
              visible: st !== null && st !== undefined && st.crew.length > 0
              title: st ? "ALREADY ABOARD " + st.short.toUpperCase() + " · " + st.expeditions.toUpperCase() : ""
              Repeater {
                model: parent.st ? parent.st.crew : []
                CrewRow { required property var modelData; person: modelData }
              }
            }

            // Timeline
            Section {
              visible: detail.l.timeline.length > 0
              title: "COUNTDOWN TIMELINE"
              Repeater {
                model: detail.l.timeline
                Row {
                  required property var modelData
                  readonly property bool past: detail.l.net + modelData.offset * 1000 <= root.nowMs
                  width: parent.width
                  spacing: Style.space(12)
                  Label {
                    width: Style.space(100)
                    text: root.fmtClock(modelData.offset)
                    color: parent.past ? root.faint : Color.accent
                    font.pixelSize: Style.font.bodySmall
                  }
                  Label {
                    width: parent.width - Style.space(112)
                    text: modelData.label
                    color: parent.past ? root.faint : root.fg
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // ================= Station view =================
          Column {
            id: stationView
            visible: root.tab !== "launches" && !root.detailLaunch
            width: parent.width
            spacing: Style.space(14)
            readonly property var st: root.tabStation

            Column {
              width: parent.width
              spacing: Style.space(4)
              Label {
                width: parent.width
                text: stationView.st ? stationView.st.name : (root.tab === "iss" ? "International Space Station" : "Tiangong space station")
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Label {
                width: parent.width
                text: stationView.st ? [stationView.st.expeditions, stationView.st.owners].filter(function(s) { return s }).join(" · ") : "Loading station data…"
                color: root.dim
              }
            }

            Grid {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(14)
              rowSpacing: Style.space(10)
              readonly property real cellW: (width - columnSpacing * 3) / 4
              KeyValue { width: parent.cellW; key: "Position"; value: root.tabPos ? Model.formatLatLon(root.tabPos) : "" }
              KeyValue { width: parent.cellW; key: "Altitude"; value: root.tabPos ? Math.round(root.tabPos.alt) + " km" : "" }
              KeyValue { width: parent.cellW; key: "Speed"; value: root.tabPos ? (Math.sqrt(398600.4418 / (6378.137 + root.tabPos.alt)) * 3600).toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + " km/h" : "" }
              KeyValue { width: parent.cellW; key: "Period"; value: root.tabPos ? root.tabPos.period.toFixed(1) + " min" : "" }
              KeyValue { width: parent.cellW; key: "Inclination"; value: root.tabEl ? root.tabEl.inclination.toFixed(2) + "°" : "" }
              KeyValue { width: parent.cellW; key: "Orbits / day"; value: root.tabEl ? root.tabEl.meanMotion.toFixed(2) : "" }
              KeyValue { width: parent.cellW; key: "Crew aboard"; value: stationView.st ? String(stationView.st.onboardCrew) : "" }
              KeyValue { width: parent.cellW; key: "Docked vehicles"; value: stationView.st ? String(stationView.st.dockedVehicles) : "" }
            }

            Section {
              title: "GROUND TRACK"
              Row {
                spacing: Style.space(6)
                TextButton { label: "Globe"; selected: stationGlobe.mode === "globe"; onClicked: stationGlobe.mode = "globe" }
                TextButton { label: "Map"; selected: stationGlobe.mode === "map"; onClicked: stationGlobe.mode = "map" }
                Item { width: Style.space(10); height: 1 }
                TextButton { label: "Follow"; selected: root.follow; onClicked: { root.follow = true; if (root.tabPos) stationGlobe.centerOn(root.tabPos.lat * 0.6, root.tabPos.lon) } }
                TextButton { label: "−"; onClicked: stationGlobe.setZoom(stationGlobe.zoom / 1.25) }
                TextButton { label: "+"; onClicked: stationGlobe.setZoom(stationGlobe.zoom * 1.25) }
              }
              Globe {
                id: stationGlobe
                width: parent.width
                bar: root.bar
                time: root.nowMs
                layers: root.tabLayers
                markers: root.tabPos ? [{ lat: root.tabPos.lat, lon: root.tabPos.lon, ch: "@", color: root.markerHex }] : []
                onInteracted: root.follow = false
              }
              Flow {
                width: parent.width
                spacing: Style.space(14)
                Legend { glyph: "@"; tint: root.fg; label: "now" }
                Legend { glyph: ":"; tint: blend(Color.accent, Color.popups.background, 0.5); label: "last 30 min" }
                Legend { glyph: "·"; tint: Color.accent; label: "next ~2 orbits" }
                Legend { glyph: "#/%"; tint: root.dim; label: "land day/night" }
              }
            }

            Section {
              visible: stationView.st !== null && stationView.st.crew.length > 0
              title: stationView.st ? "CREW ABOARD · " + stationView.st.crew.length : ""
              Repeater {
                model: stationView.st ? stationView.st.crew : []
                CrewRow { required property var modelData; person: modelData }
              }
            }

            Section {
              visible: root.tabUpcoming.length > 0
              title: "FLIGHTS TO " + (root.tab === "iss" ? "ISS" : "TIANGONG")
              Repeater {
                model: root.tabUpcoming
                LinkRow {
                  required property var modelData
                  icon: modelData.crew.length > 0 ? "󰀄" : "󱓞"
                  live: modelData.webcastLive
                  title: modelData.missionName + "  ·  " + Model.countdown(modelData.net, root.nowMs)
                  subtitle: modelData.rocketName + " · " + Qt.formatDateTime(new Date(modelData.net), "ddd d MMM HH:mm") + " · " + modelData.status
                  url: ""
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail(modelData)
                  }
                }
              }
            }

            Section {
              title: "LINKS"
              LinkRow {
                visible: root.tab === "iss"
                icon: "󰗃"
                title: "NASA+ live coverage"
                subtitle: "plus.nasa.gov"
                url: "https://plus.nasa.gov/"
              }
              LinkRow {
                visible: root.tab === "iss"
                icon: "󰖟"
                title: "Spot the Station: when it's visible from your location"
                subtitle: "spotthestation.nasa.gov"
                url: "https://spotthestation.nasa.gov/"
              }
              LinkRow {
                icon: "󰖟"
                title: "Live tracker on N2YO"
                subtitle: "n2yo.com"
                url: "https://www.n2yo.com/?s=" + root.tabNorad
              }
            }

            Caption {
              text: "←→ SPIN · W/S TILT · +/− ZOOM · M MAP · F FOLLOW  —  ORBIT: CELESTRAK · CREW: THE SPACE DEVS"
              font.pixelSize: Style.font.caption - 1
            }
          }
        }
      }
    }
  }
}
