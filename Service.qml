import QtQuick
import Quickshell.Io

Item {
  id: root

  property var widgets: []

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
          + ", feed " + (w.feedInstalled ? "installed" : "not installed")
      })
    }
  }
}
