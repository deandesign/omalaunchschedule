import QtQuick
import qs.Commons
import qs.Ui

// Rocket icon in the bar, with an optional countdown to the next launch.
// It lights up (active colour) while any launch webcast is live.
BarWidget {
  id: root
  moduleName: "io.github.deandesign.launch-schedule"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string icon: setting("icon", "󱓞")
  readonly property string countdown: panelLoader.item ? panelLoader.item.barCountdown : ""
  readonly property bool launching: panelLoader.item ? panelLoader.item.launchActive === true : false
  readonly property bool showCountdown: countdown !== "" && !vertical

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  // WidgetButton supplies sizing, hover, clicks and tooltip; its own label is
  // hidden so the rocket can animate independently of the countdown text.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    text: root.showCountdown ? root.icon + " " + root.countdown : root.icon
    fontSize: root.showCountdown ? Style.font.body : Style.bar.iconFont
    fixedWidth: root.showCountdown || root.vertical ? -1 : Style.bar.iconSlot
    tooltipText: root.opened || !panelLoader.item ? "" : panelLoader.item.tooltip

    onPressed: function(b) {
      if (!root.bar || !panelLoader.item) return
      if (b === Qt.MiddleButton) panelLoader.item.refresh(true)
      else root.togglePanel()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        id: rocket
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.icon
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering

        transform: Translate { id: lift }

        // Lift-off: a short climb up-and-right with a little engine shake,
        // then it resets and goes again.
        SequentialAnimation {
          running: root.launching
          loops: Animation.Infinite
          onStopped: { lift.x = 0; lift.y = 0; rocket.opacity = 1 }

          ParallelAnimation {
            SequentialAnimation {
              loops: 4
              NumberAnimation { target: lift; property: "x"; to: 0.6; duration: 45 }
              NumberAnimation { target: lift; property: "x"; to: -0.6; duration: 45 }
            }
          }
          ParallelAnimation {
            NumberAnimation { target: lift; property: "x"; to: 3; duration: 520; easing.type: Easing.InQuad }
            NumberAnimation { target: lift; property: "y"; to: -3; duration: 520; easing.type: Easing.InQuad }
            NumberAnimation { target: rocket; property: "opacity"; to: 0; duration: 520; easing.type: Easing.InQuad }
          }
          PropertyAction { target: lift; property: "x"; value: -3 }
          PropertyAction { target: lift; property: "y"; value: 3 }
          ParallelAnimation {
            NumberAnimation { target: lift; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: rocket; property: "opacity"; to: 1; duration: 260 }
          }
          PauseAnimation { duration: 500 }
        }
      }

      Text {
        visible: root.showCountdown
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.countdown
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }
  }
}
