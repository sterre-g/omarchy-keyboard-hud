import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string feedPath: root.runtimeDir + "/sterre-keyboard-hud.json"
  readonly property string configPath: root.runtimeDir + "/sterre-keyboard-hud.conf"

  property var history: []
  property var down: []
  property double lastStamp: -1

  property string strip: "chords"
  property bool map: false
  property string order: "strip-above"
  property string position: "bottom"
  property real mapScale: 1
  property int lingerMs: 2000
  property int historyCount: 4
  property string overrideLayout: ""
  property string overrideVariant: ""
  property bool forceQwerty: false

  // Labels come from the keymap the user actually has loaded, so the map reads
  // colemak on a colemak machine without shipping a table per layout.
  property var keymapLabels: ({})
  property var keyboard: null
  property string keymapName: ""

  readonly property bool showStrip: root.strip !== "off" && root.history.length > 0
  readonly property bool showMap: root.map
  readonly property bool showing: root.showStrip || root.showMap
  readonly property real unit: Math.round(Style.space(26) * root.mapScale)
  readonly property real gap: Math.max(2, Math.round(root.unit * 0.08))

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function applyConfig(raw) {
    var data = {}
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      data = {}
    }

    root.strip = Model.normalizeStrip(data.strip)
    root.map = Model.normalizeBool(data.map)
    root.order = Model.normalizeOrder(data.order)
    root.position = Model.normalizePosition(data.position)
    root.mapScale = Model.normalizeScale(data.scale)
    root.lingerMs = Math.max(300, Math.min(10000, Number(data.lingerMs) || 2000))
    root.historyCount = Math.max(1, Math.min(10, Number(data.historyCount) || 4))

    var nextLayout = String(data.layout || "")
    var nextVariant = String(data.variant || "")
    var nextQwerty = Model.normalizeBool(data.qwerty)
    if (nextLayout !== root.overrideLayout || nextVariant !== root.overrideVariant
      || nextQwerty !== root.forceQwerty) {
      root.overrideLayout = nextLayout
      root.overrideVariant = nextVariant
      root.forceQwerty = nextQwerty
      root.detectLayout()
    }

    if (!root.map) root.down = []
    if (root.strip === "off") root.history = []
  }

  function ingest(raw) {
    var event = Model.parseFeed(raw)
    if (!event) return

    root.down = event.down
    if (event.code === null) return
    if (event.t === root.lastStamp) return
    root.lastStamp = event.t
    root.history = Model.stamp(Model.pushEvent(root.history, event, root.historyCount, root.keymapLabels), Date.now())
  }

  function overrideSpec() {
    return Model.overrideFrom(root.forceQwerty, root.overrideLayout, root.overrideVariant)
  }

  function detectLayout() {
    if (!devices.running) devices.running = true
  }

  function adoptDevices(raw) {
    var data = null
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    root.keyboard = Model.pickKeyboard(data && data.keyboards ? data.keyboards : [])
    root.keymapName = Model.layoutName(root.keyboard, root.overrideSpec())
    keymap.command = Model.keymapCommand(root.keyboard, root.overrideSpec())
    keymap.running = true
  }

  Component.onCompleted: root.detectLayout()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // A kb_variant changed in the config reloads rather than raising a layout
      // switch, so both events have to re-read the keymap.
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.detectLayout()
    }
  }

  FileView {
    path: root.feedPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.ingest(text())
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
  }

  Process {
    id: devices
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.adoptDevices(text)
    }
  }

  Process {
    id: keymap
    command: ["xkbcli", "compile-keymap", "--layout", "us"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keymapLabels = Model.parseKeymap(text)
    }
  }

  Timer {
    interval: 250
    running: root.history.length > 0
    repeat: true
    onTriggered: root.history = Model.expire(root.history, Date.now(), root.lingerMs)
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window

      required property var modelData

      screen: window.modelData
      visible: root.showing
      color: "transparent"
      WlrLayershell.namespace: "sterre-keyboard-hud"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Visual only. Without an empty input region this surface swallows every
      // click inside it, and it is a full width strip along an edge, so it
      // covers whatever the bar has there. It is a caption, not a UI.
      mask: Region {}

      // The surface stays full width whatever the position is, so the cards can
      // sit against either side without resizing the layer on every change.
      readonly property string vertical: Model.positionVertical(root.position)
      readonly property string horizontal: Model.positionHorizontal(root.position)

      anchors {
        top: window.vertical !== "bottom"
        bottom: window.vertical !== "top"
        left: true
        right: true
      }

      implicitHeight: stack.implicitHeight + Style.space(40)

      Column {
        id: stack

        // The column spans the screen and each card places itself inside it.
        // Sizing the column to its cards instead does not work: the cards
        // anchor to its centre, so it resolves to full width anyway and moving
        // it does nothing, which is why every position drew in the middle.
        readonly property real edge: Style.space(20)
        x: stack.edge
        width: parent.width - stack.edge * 2

        anchors.verticalCenter: window.vertical === "middle" ? parent.verticalCenter : undefined
        anchors.bottom: window.vertical === "bottom" ? parent.bottom : undefined
        anchors.top: window.vertical === "top" ? parent.top : undefined
        anchors.margins: stack.edge
        spacing: Style.spacing.md

        // The strip and the map are the same two children in either order, so
        // "above" and "below" is one setting rather than two layouts.
        Loader {
          x: window.horizontal === "left" ? 0
            : window.horizontal === "right" ? stack.width - width
            : (stack.width - width) / 2
          active: root.showStrip && Model.stripAbove(root.order)
          visible: active
          sourceComponent: stripCard
        }

        Loader {
          x: window.horizontal === "left" ? 0
            : window.horizontal === "right" ? stack.width - width
            : (stack.width - width) / 2
          active: root.showMap
          visible: active
          sourceComponent: mapCard
        }

        Loader {
          x: window.horizontal === "left" ? 0
            : window.horizontal === "right" ? stack.width - width
            : (stack.width - width) / 2
          active: root.showStrip && !Model.stripAbove(root.order)
          visible: active
          sourceComponent: stripCard
        }
      }
    }
  }

  Component {
    id: stripCard

    Rectangle {
      implicitWidth: chips.implicitWidth + Style.spacing.panelPadding * 2
      implicitHeight: chips.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: Color.menu.border

      Row {
        id: chips
        anchors.centerIn: parent
        spacing: Style.spacing.md

        Repeater {
          model: root.history

          Rectangle {
            required property var modelData

            implicitWidth: chipText.implicitWidth + Style.spacing.lg * 2
            implicitHeight: chipText.implicitHeight + Style.spacing.sm * 2
            radius: Style.cornerRadius
            color: Color.menu.selectedBackground
            border.width: 1
            border.color: Qt.darker(Color.menu.text, 2.2)

            Text {
              id: chipText
              anchors.centerIn: parent
              text: Model.displayText(parent.modelData)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              color: Color.menu.text
            }
          }
        }
      }
    }
  }

  Component {
    id: mapCard

    Rectangle {
      implicitWidth: keyRows.implicitWidth + Style.spacing.md * 2
      implicitHeight: keyRows.implicitHeight + Style.spacing.md * 2 + caption.implicitHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: Color.menu.border

      Column {
        id: keyRows
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.md
        spacing: root.gap

        Repeater {
          model: Model.LAYOUT

          Row {
            required property var modelData

            spacing: root.gap

            Repeater {
              model: parent.modelData

              Rectangle {
                required property var modelData

                readonly property int code: modelData[0]
                readonly property real units: modelData[2]
                readonly property bool held: Model.isDown(root.down, code)

                width: root.unit * units + root.gap * (units - 1)
                height: root.unit
                radius: Math.max(2, Math.round(root.unit * 0.12))
                color: held ? Color.accent : Color.menu.selectedBackground
                border.width: 1
                border.color: held ? Color.accent : Qt.darker(Color.menu.text, 2.4)

                Behavior on color {
                  ColorAnimation { duration: 60 }
                }

                Text {
                  anchors.centerIn: parent
                  text: Model.labelFor(parent.code, root.keymapLabels)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Math.max(8, Math.round(root.unit * 0.34))
                  color: parent.held ? Color.menu.background : Color.menu.text
                  elide: Text.ElideRight
                  width: parent.width - Style.spacing.xs * 2
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }
        }
      }

      Text {
        id: caption
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.xs
        text: root.forceQwerty ? root.keymapName + "  (forced qwerty)" : root.keymapName
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        color: Qt.darker(Color.menu.text, 1.8)
      }
    }
  }
}
