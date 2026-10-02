import QtQuick
import qs.Commons
import "Model.js" as Model

// Text-mode globe. Drag to spin, wheel to zoom, the M key (or the toggle in
// the parent) flips between orthographic globe and flat map.
Item {
  id: root

  property QtObject bar: null
  property real viewLat: 20
  property real viewLon: 0
  property real zoom: 1
  property string mode: "globe"     // "globe" | "map"
  property real time: Date.now()
  property var layers: []
  property var markers: []
  property int maxCols: 76

  property color foreground: bar ? bar.foreground : Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent

  readonly property bool dragging: dragArea.pressed

  signal interacted()

  function mix(a, b, t) {
    function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(a.r * t + b.r * (1 - t)) + h(a.g * t + b.g * (1 - t)) + h(a.b * t + b.b * (1 - t))
  }

  function spin(dLon, dLat) {
    viewLon = ((viewLon + dLon + 540) % 360) - 180
    viewLat = Math.max(-85, Math.min(85, viewLat + dLat))
    interacted()
  }

  function setZoom(z) {
    zoom = Math.max(0.6, Math.min(6, z))
    interacted()
  }

  function centerOn(lat, lon) {
    viewLat = Math.max(-85, Math.min(85, lat))
    viewLon = lon
  }

  readonly property var palette: ({
    land: mix(foreground, background, 0.85),
    landNight: mix(foreground, background, 0.45),
    ocean: mix(accent, background, 0.4),
    oceanNight: mix(accent, background, 0.15),
    grid: mix(foreground, background, 0.3)
  })

  // Measure a cell exactly as the rich text lays it out (line spacing in
  // RichText differs from FontMetrics.height).
  Text {
    id: probe
    visible: false
    textFormat: Text.RichText
    font: globeText.font
    lineHeight: 1.0
    text: "XXXXXXXXXX<br>X<br>X<br>X<br>X<br>X<br>X<br>X<br>X<br>X"
  }
  readonly property real cellW: Math.max(1, probe.contentWidth / 10)
  readonly property real cellH: Math.max(1, probe.contentHeight / 10)

  readonly property int cols: Math.max(24, Math.min(maxCols, Math.floor(width / cellW) - 1))
  // Rendered cell height / width, so the globe comes out round in any font.
  readonly property real aspect: Math.max(1.4, Math.min(3, cellH / cellW))
  readonly property int rows: Math.round(cols / aspect * (mode === "map" ? 0.5 : 1) + (mode === "map" ? 0 : 1))

  implicitHeight: globeText.implicitHeight

  Text {
    id: globeText
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.RichText
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
    lineHeight: 1.0
    color: root.foreground
    text: Model.renderGlobe({
      cols: root.cols, rows: root.rows,
      lat: root.viewLat, lon: root.viewLon, zoom: root.zoom,
      mode: root.mode, time: root.time, aspect: root.aspect,
      colors: root.palette,
      layers: root.layers, markers: root.markers
    })
  }

  MouseArea {
    id: dragArea
    anchors.fill: globeText
    preventStealing: true
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real lastX: 0
    property real lastY: 0

    onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
    onPositionChanged: function(mouse) {
      var degPerPx = 180 / Math.max(1, width) / root.zoom * (root.mode === "map" ? 2 : 1)
      root.spin(-(mouse.x - lastX) * degPerPx, (mouse.y - lastY) * degPerPx)
      lastX = mouse.x; lastY = mouse.y
    }
    onDoubleClicked: root.setZoom(root.zoom * 1.5)
    onWheel: function(wheel) {
      root.setZoom(root.zoom * (wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15))
      wheel.accepted = true
    }
  }
}
