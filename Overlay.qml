pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property var paths: Model.statePaths(Quickshell.env("XDG_RUNTIME_DIR"))
  // Both stay empty until the private directory has been created and checked.
  // The bar widget asks for the same directory; the call is idempotent, and
  // making it here as well is what keeps a watch from being set on a path
  // whose parent does not exist yet.
  property string feedPath: ""
  property string configPath: ""

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
  property string formSetting: "auto"

  // The service picks the keyboard for the whole shell; this compiles its
  // keymap. Labels come from the keymap the user actually has loaded, so the
  // map reads colemak on a colemak machine without a table per layout.
  property var service: null
  readonly property var keyboard: root.service ? root.service.keyboard : null
  property var keymapLabels: ({})
  property string keymapName: ""
  readonly property var board: Model.layoutFor(Model.keyboardForm(root.formSetting, root.keyboard))

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
    var data = Model.parseBounded(raw, "config")
    if (!data) return

    root.strip = Model.normalizeStrip(data.strip)
    root.map = Model.normalizeBool(data.map)
    root.order = Model.normalizeOrder(data.order)
    root.position = Model.normalizePosition(data.position)
    root.mapScale = Model.normalizeScale(data.scale)
    root.lingerMs = Math.max(300, Math.min(10000, Number(data.lingerMs) || 2000))
    root.historyCount = Math.max(1, Math.min(10, Number(data.historyCount) || 4))
    root.formSetting = Model.normalizeForm(data.form)

    var nextLayout = String(data.layout || "")
    var nextVariant = String(data.variant || "")
    var nextQwerty = Model.normalizeBool(data.qwerty)
    if (nextLayout !== root.overrideLayout || nextVariant !== root.overrideVariant
      || nextQwerty !== root.forceQwerty) {
      root.overrideLayout = nextLayout
      root.overrideVariant = nextVariant
      root.forceQwerty = nextQwerty
      root.compileKeymap()
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

  // A switch while a compile is still running is picked up when it ends, since
  // a running Process cannot be restarted with a new command.
  property bool compileAgain: false

  function compileKeymap() {
    if (keymap.running) {
      root.compileAgain = true
      return
    }
    root.keymapName = Model.layoutName(root.keyboard, root.overrideSpec())
    keymap.command = Model.keymapCommand(root.keyboard, root.overrideSpec())
    keymap.running = true
  }

  function resolveService() {
    if (root.service || !root.shell || typeof root.shell.serviceFor !== "function") return
    root.service = root.shell.serviceFor((root.manifest && root.manifest.id) || "sterre.keyboard-hud")
  }

  onKeyboardChanged: root.compileKeymap()

  Component.onCompleted: {
    if (root.paths.dir !== "") stateDir.running = true
    root.compileKeymap()
  }

  onShellChanged: root.resolveService()

  // serviceFor() is a plain function, so a binding would never see the service
  // arrive; poll until it has.
  Timer {
    interval: 250
    repeat: true
    running: root.service === null
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  Process {
    id: stateDir
    command: Model.stateDirCommand(root.paths.dir)
    onExited: function (exitCode) {
      if (exitCode !== 0) return
      root.feedPath = root.paths.feed
      root.configPath = root.paths.config
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
    id: keymap
    command: ["xkbcli", "compile-keymap", "--layout", "us"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keymapLabels = Model.parseKeymap(text)
    }
    onRunningChanged: {
      keymapDeadline.running = keymap.running
      if (!keymap.running && root.compileAgain) {
        root.compileAgain = false
        root.compileKeymap()
      }
    }
  }

  // waitForEnd holds the output until the process closes stdout, so one that
  // hangs is a collector that never finishes, and a layout switch while it
  // hangs could never be compiled. Give it five seconds and then take it back.
  Timer {
    id: keymapDeadline
    interval: 5000
    onTriggered: if (keymap.running) keymap.signal(15)
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

        y: window.vertical === "top" ? stack.edge
          : window.vertical === "bottom" ? parent.height - stack.height - stack.edge
          : (parent.height - stack.height) / 2
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
      color: Commons.Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.menu.border

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
            color: Commons.Color.menu.selectedBackground
            border.width: 1
            border.color: Qt.darker(Commons.Color.menu.text, 2.2)

            Text {
              id: chipText
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: Model.displayText(parent.modelData)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              color: Commons.Color.menu.text
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
      color: Commons.Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.menu.border

      Column {
        id: keyRows
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.md
        spacing: root.gap

        Repeater {
          model: root.board

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
                color: held ? Commons.Color.accent : Commons.Color.menu.selectedBackground
                border.width: 1
                border.color: held ? Commons.Color.accent : Qt.darker(Commons.Color.menu.text, 2.4)

                Behavior on color {
                  ColorAnimation { duration: Style.duration(60) }
                }

                // The lower half of an ISO Enter reaches up through the row gap
                // into the upper half, so the two read as one key.
                Rectangle {
                  visible: Model.isTail(parent.modelData)
                  anchors.bottom: parent.top
                  anchors.bottomMargin: -parent.radius
                  anchors.right: parent.right
                  width: parent.width
                  height: root.gap + parent.radius * 2
                  color: parent.color
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: Model.keyLabel(parent.modelData, root.keymapLabels)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Math.max(8, Math.round(root.unit * 0.34))
                  color: parent.held ? Commons.Color.menu.background : Commons.Color.menu.text
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
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.xs
        text: root.forceQwerty ? root.keymapName + "  (forced qwerty)" : root.keymapName
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        color: Qt.darker(Commons.Color.menu.text, 1.8)
      }
    }
  }
}
