import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "sterre.keyboard-hud"
  manageIpc: false

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string configPath: root.runtimeDir + "/sterre-keyboard-hud.conf"

  property string strip: Model.normalizeStrip(root.setting("strip", "chords"))
  property bool map: Model.normalizeBool(root.setting("map", false))
  property string order: Model.normalizeOrder(root.setting("order", "strip-above"))
  property string position: Model.normalizePosition(root.setting("position", "bottom"))
  property real mapScale: Model.normalizeScale(root.setting("scale", 1))
  property bool forceQwerty: Model.normalizeBool(root.setting("qwerty", false))
  property bool feedInstalled: false
  property bool settingsApplied: false
  property string detectedLayout: ""

  readonly property bool anythingOn: root.strip !== "off" || root.map

  readonly property string screenName: root.QsWindow.window && root.QsWindow.window.screen
    ? root.QsWindow.window.screen.name
    : ""
  readonly property bool onFocusedScreen: Hyprland.focusedMonitor && root.screenName !== ""
    ? Hyprland.focusedMonitor.name === root.screenName
    : false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Bar.injectProps assigns settings through a Qt.callLater, so a freshly
  // built widget runs its own Component.onCompleted before it has been told
  // anything. Writing then would publish the manifest defaults over a config
  // the running shell has been keeping correct, which is what made a plugin
  // reload turn the HUD back on.
  function writeConfig() {
    if (!root.settingsApplied) return
    config.setText(JSON.stringify({
      strip: root.strip,
      map: root.map,
      order: root.order,
      position: root.position,
      scale: root.mapScale,
      lingerMs: Math.max(300, Math.min(10000, Number(root.setting("lingerMs", 2000)))),
      historyCount: Math.max(1, Math.min(10, Number(root.setting("historyCount", 4)))),
      qwerty: root.forceQwerty,
      layout: String(root.setting("layout", "")),
      variant: String(root.setting("variant", ""))
    }, null, 2) + "\n")
  }

  // Both monitors get their own copy of this widget and both write the config,
  // so each one reads it back. For a switch that decides whether keystrokes are
  // recorded, a stale copy re-asserting itself is not a cosmetic problem.
  function adoptConfig(raw) {
    var data = {}
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    root.strip = Model.normalizeStrip(data.strip)
    root.map = Model.normalizeBool(data.map)
    root.order = Model.normalizeOrder(data.order)
    root.position = Model.normalizePosition(data.position)
    root.mapScale = Model.normalizeScale(data.scale)
    root.forceQwerty = Model.normalizeBool(data.qwerty)
  }

  // configPath is under XDG_RUNTIME_DIR, which systemd wipes at logout, and
  // Component.onCompleted rebuilds it from the stored settings. So a change
  // made here that is not written back to shell.json survives until the next
  // reload and is then replaced by the manifest default. Turning the HUD off
  // before a reboot and finding it recording again after login is that bug.
  function persist(patch) {
    var entry = Model.settingsWith(root.settings, patch)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.writeConfig()
  }

  function setQwerty(value) {
    root.forceQwerty = value === true
    root.persist({ qwerty: root.forceQwerty })
    devices.running = true
  }

  function setStrip(value) {
    root.strip = Model.normalizeStrip(value)
    root.persist({ strip: root.strip })
  }

  function setMap(value) {
    root.map = value === true
    root.persist({ map: root.map })
  }

  function setOrder(value) {
    root.order = Model.normalizeOrder(value)
    root.persist({ order: root.order })
  }

  function setPosition(value) {
    root.position = Model.normalizePosition(value)
    root.persist({ position: root.position })
  }

  function setScale(value) {
    root.mapScale = Model.normalizeScale(value)
    root.persist({ scale: root.mapScale })
  }

  function turnOff() {
    root.strip = "off"
    root.map = false
    root.persist({ strip: "off", map: false })
  }

  function checkFeed() {
    if (!feedProbe.running) feedProbe.running = true
  }

  function adoptDevices(raw) {
    var data = null
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    var keyboard = Model.pickKeyboard(data && data.keyboards ? data.keyboards : [])
    var override = Model.overrideFrom(root.forceQwerty,
      String(root.setting("layout", "")), String(root.setting("variant", "")))
    root.detectedLayout = Model.layoutName(keyboard, override)
  }

  Component.onCompleted: {
    root.checkFeed()
    devices.running = true
  }

  onSettingsChanged: {
    root.settingsApplied = true
    root.strip = Model.normalizeStrip(root.setting("strip", "chords"))
    root.map = Model.normalizeBool(root.setting("map", false))
    root.order = Model.normalizeOrder(root.setting("order", "strip-above"))
    root.position = Model.normalizePosition(root.setting("position", "bottom"))
    root.mapScale = Model.normalizeScale(root.setting("scale", 1))
    root.forceQwerty = Model.normalizeBool(root.setting("qwerty", false))
    root.writeConfig()
  }

  onOpenedChanged: if (opened) {
    root.checkFeed()
    devices.running = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: config
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.adoptConfig(text())
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkFeed()
  }

  Process {
    id: feedProbe
    command: ["grep", "-qF", "sterre.keyboard-hud", Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"]
    onExited: function (exitCode) { root.feedInstalled = exitCode === 0 }
  }

  Process {
    id: devices
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.adoptDevices(text)
    }
  }

  IpcHandler {
    target: "sterre.keyboard-hud"
    enabled: root.onFocusedScreen

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function strip(value: string): string {
      root.setStrip(value)
      return root.strip
    }
    function map(value: string): string {
      root.setMap(value === "on" || value === "true" || value === "1")
      return root.map ? "on" : "off"
    }
    function qwerty(value: string): string {
      root.setQwerty(value === "on" || value === "true" || value === "1")
      return root.forceQwerty ? "on" : "off"
    }
    function order(value: string): string {
      root.setOrder(value)
      return root.order
    }
    function off(): string {
      root.turnOff()
      return "off"
    }
    function status(): string {
      return "strip " + root.strip + ", map " + (root.map ? "on" : "off")
        + ", " + root.order + ", " + root.position
        + ", layout " + (root.detectedLayout === "" ? "unknown" : root.detectedLayout)
        + ", feed " + (root.feedInstalled ? "installed" : "not installed")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf11c"
    active: root.anythingOn
    tooltipText: root.feedInstalled
      ? "Keyboard HUD: strip " + root.strip + ", map " + (root.map ? "on" : "off")
      : "Keyboard HUD: run bin/keyfeed-install first"
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.anythingOn) root.turnOff()
        else root.setStrip("chords")
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "c") root.setStrip("chords")
        else if (t === "a") root.setStrip("all")
        else if (t === "s") root.setStrip("off")
        else if (t === "m") root.setMap(!root.map)
        else if (t === "o") root.setOrder(Model.stripAbove(root.order) ? "strip-below" : "strip-above")
        else if (t === "x") root.turnOff()
        else if (t === "q") root.setQwerty(!root.forceQwerty)
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
          spacing: Style.space(10)

          PanelSectionHeader {
            width: parent.width
            text: "Keyboard HUD"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: !root.feedInstalled
            text: "The key feed is not wired into Hyprland yet. Run bin/keyfeed-install from the plugin folder."
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Color.urgent
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            width: parent.width
            text: "Key strip"
            foreground: root.dim
            fontFamily: root.fontFamily
          }

          Row {
            spacing: Style.spacing.controlGap

            Button {
              text: "Chords"
              tooltipText: "Modifier combinations and keys that carry no text"
              bordered: true
              selected: root.strip === "chords"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setStrip("chords")
            }

            Button {
              text: "Everything"
              tooltipText: "Every key, including what you type"
              bordered: true
              selected: root.strip === "all"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setStrip("all")
            }

            Button {
              text: "Off"
              bordered: true
              selected: root.strip === "off"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setStrip("off")
            }
          }

          Toggle {
            width: parent.width
            label: root.map ? "Showing the keyboard map" : "Keyboard map is off"
            description: "While this is on, every key you press lights up on screen, including in other windows."
            checked: root.map
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.setMap(!root.map)
          }

          Text {
            width: parent.width
            visible: root.strip === "all"
            text: "Everything mode puts each key you type on screen, including into password fields."
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Color.urgent
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            width: parent.width
            text: "Stacking"
            foreground: root.dim
            fontFamily: root.fontFamily
          }

          Row {
            spacing: Style.spacing.controlGap

            Button {
              text: "Strip above"
              bordered: true
              selected: Model.stripAbove(root.order)
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setOrder("strip-above")
            }

            Button {
              text: "Strip below"
              bordered: true
              selected: !Model.stripAbove(root.order)
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setOrder("strip-below")
            }
          }

          PanelSectionHeader {
            width: parent.width
            text: "Where"
            foreground: root.dim
            fontFamily: root.fontFamily
          }

          Row {
            spacing: Style.spacing.controlGap

            Repeater {
              model: Model.POSITIONS

              Button {
                required property var modelData

                text: modelData
                bordered: true
                selected: root.position === modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.setPosition(modelData)
              }
            }
          }

          PanelSectionHeader {
            width: parent.width
            text: "Map size"
            foreground: root.dim
            fontFamily: root.fontFamily
          }

          Row {
            spacing: Style.spacing.controlGap

            Repeater {
              model: [0.75, 1, 1.25, 1.5]

              Button {
                required property var modelData

                text: String(modelData)
                bordered: true
                selected: Math.abs(root.mapScale - modelData) < 0.01
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.setScale(modelData)
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            width: parent.width
            text: "Labels"
            foreground: root.dim
            fontFamily: root.fontFamily
          }

          Row {
            spacing: Style.spacing.controlGap

            Button {
              text: "Your layout"
              tooltipText: "Label the map from the keyboard layout you are actually using"
              bordered: true
              selected: !root.forceQwerty
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setQwerty(false)
            }

            Button {
              text: "Qwerty"
              tooltipText: "Draw a qwerty board regardless, which is what most viewers expect"
              bordered: true
              selected: root.forceQwerty
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setQwerty(true)
            }
          }

          Text {
            width: parent.width
            text: "Layout: " + (root.detectedLayout === "" ? "detecting" : root.detectedLayout)
              + (root.forceQwerty ? "  (forced qwerty)" : "")
              + "\nc chords, a everything, s strip off, m map, o order, q qwerty, x all off"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
