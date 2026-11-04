import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// One instance for the whole shell. The bar widget exists once per monitor, so
// everything that would otherwise run once per monitor lives here: the IPC
// target, the check for the Hyprland side of the feed, the keyboard lookup and
// the push of the recording switches into keyfeed.lua.
Item {
  id: root

  property var widgets: []

  property bool feedInstalled: false
  // The keyboard the labels follow, as `hyprctl -j devices` describes it.
  property var keyboard: null
  property string namedKeyboard: ""

  property string pushedStrip: ""
  property string pushedMap: ""

  function registerWidget(widget) {
    if (!widget || root.widgets.indexOf(widget) !== -1) return
    root.widgets = root.widgets.concat([widget])
  }

  function unregisterWidget(widget) {
    root.widgets = root.widgets.filter(function (w) { return w !== widget })
  }

  function focusedWidget() {
    for (var i = 0; i < root.widgets.length; i++) {
      if (root.widgets[i] && root.widgets[i].onFocusedScreen === true) return root.widgets[i]
    }
    return root.widgets.length > 0 ? root.widgets[0] : null
  }

  // Every widget reads the shared config file back, so a setting changed
  // through one reaches all of them. The panel opens where you are looking.
  function withFocused(action) {
    var widget = root.focusedWidget()
    return widget ? action(widget) : "no keyboard HUD on the bar"
  }

  function isOn(value) {
    return value === "on" || value === "true" || value === "1"
  }

  function checkFeed() {
    if (!feedProbe.running) feedProbe.running = true
  }

  function detectKeyboard() {
    if (!devices.running) devices.running = true
  }

  function adoptDevices(raw) {
    var data = Model.parseBounded(raw, "devices")
    if (!data) return
    var next = Model.pickKeyboard(data.keyboards, root.namedKeyboard)
    if (JSON.stringify(next) !== JSON.stringify(root.keyboard)) root.keyboard = next
  }

  // Tell the Hyprland side the two settings that decide whether a keypress is
  // recorded at all. Each widget asks whenever it writes its config, so only a
  // change goes out, unless a reload has just reset the script to off. Both
  // values are picked from a fixed set here, so nothing that arrives from
  // outside reaches the eval.
  function pushFeedConfig(strip, map, force) {
    var safeStrip = strip === "all" || strip === "chords" ? strip : "off"
    var safeMap = map === true ? "true" : "false"
    if (!force && safeStrip === root.pushedStrip && safeMap === root.pushedMap) return
    root.pushedStrip = safeStrip
    root.pushedMap = safeMap
    Quickshell.execDetached(["hyprctl", "eval",
      "__sterre_keyboard_hud_config(\"" + safeStrip + "\", " + safeMap + ")"])
  }

  Component.onCompleted: root.detectKeyboard()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "activelayout") {
        var named = Model.eventKeyboardName(event)
        if (named !== "") root.namedKeyboard = named
        root.detectKeyboard()
      } else if (name === "configreloaded") {
        // A reload re-runs keyfeed.lua, which starts off until told otherwise,
        // and a kb_variant change arrives as a reload rather than a switch.
        if (root.pushedStrip !== "") root.pushFeedConfig(root.pushedStrip, root.pushedMap === "true", true)
        root.detectKeyboard()
      }
    }
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
    onRunningChanged: deviceDeadline.running = devices.running
  }

  // waitForEnd holds the collected output until the process closes its stdout,
  // so a hyprctl that hangs is a collector that never finishes and a keyboard
  // nobody learns. Give it five seconds and then take it back.
  Timer {
    id: deviceDeadline
    interval: 5000
    onTriggered: if (devices.running) devices.signal(15)
  }

  IpcHandler {
    target: "sterre.keyboard-hud"

    function open(): void { root.withFocused(function (w) { w.open() }) }
    function close(): void { root.widgets.forEach(function (w) { if (w) w.close() }) }
    function toggle(): void { root.withFocused(function (w) { w.toggle() }) }
    function strip(value: string): string {
      return root.withFocused(function (w) {
        w.setStrip(value)
        return w.strip
      })
    }
    function map(value: string): string {
      return root.withFocused(function (w) {
        w.setMap(root.isOn(value))
        return w.map ? "on" : "off"
      })
    }
    function qwerty(value: string): string {
      return root.withFocused(function (w) {
        w.setQwerty(root.isOn(value))
        return w.forceQwerty ? "on" : "off"
      })
    }
    function order(value: string): string {
      return root.withFocused(function (w) {
        w.setOrder(value)
        return w.order
      })
    }
    function position(value: string): string {
      return root.withFocused(function (w) {
        w.setPosition(value)
        return w.position
      })
    }
    function off(): string {
      return root.withFocused(function (w) {
        w.turnOff()
        return "off"
      })
    }
    function status(): string {
      return root.withFocused(function (w) {
        return "strip " + w.strip + ", map " + (w.map ? "on" : "off")
          + ", " + w.order + ", " + w.position
          + ", layout " + (w.detectedLayout === "" ? "unknown" : w.detectedLayout)
          + " from " + (root.keyboard ? root.keyboard.name : "no keyboard")
          + ", feed " + (root.feedInstalled ? "installed" : "not installed")
      })
    }
  }
}
