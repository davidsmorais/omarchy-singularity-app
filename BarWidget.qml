import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SingularityApp bar widget for Omarchy.
// Shows today's open tasks in the bar; click to open the daily planner panel.
BarWidget {
  id: root
  moduleName: "david.singularity"

  readonly property var singularity: bar && bar.shell
    ? bar.shell.serviceFor("david.singularity") : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Color.muted

  readonly property int taskCount: singularity ? singularity.todayCount : 0
  readonly property bool hasTasks: taskCount > 0
  readonly property string tooltip: {
    if (!hasToken) return "Singularity App — no API token set"
    if (loading) return "Singularity App — loading tasks…"
    if (error !== "") return "Singularity App — " + error
    if (taskCount === 0) return "Singularity App — no tasks for today"
    return "Singularity App — " + taskCount + " task" + (taskCount === 1 ? "" : "s") + " for today"
  }

  readonly property bool loading: singularity ? singularity.loading : false
  readonly property string error: singularity ? singularity.error : ""
  readonly property bool hasToken: (settings.apiToken || "") !== ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // shell.json only stores keys the user has actually changed, so missing
  // keys need the same defaults Service.qml starts with.
  function normalizedSettings() {
    return {
      apiToken: settings.apiToken || "",
      refreshMinutes: settings.refreshMinutes || 5,
      showCompleted: settings.showCompleted || "off",
      maxTasks: settings.maxTasks || 50
    }
  }

  // Pushes this widget's settings into the shared service, but never lets a
  // stale/empty snapshot stomp a token the service already has. `settings`
  // here is the bar's own schema-bound copy of shell.json; it can briefly
  // lag behind a save the service just made itself (saveApiToken/saveSetting
  // write straight to `service.settings` before the bar's own reactive copy
  // has caught up), and re-pushing that lagging snapshot right after would
  // silently revert the save — this was the "API token doesn't persist" bug.
  function pushSettingsTo(svc) {
    if (!svc) return
    var next = normalizedSettings()
    if (next.apiToken === "" && svc.settings.apiToken !== "") return
    svc.settings = next
    if (root.hasToken) svc.refresh()
  }

  onSettingsChanged: pushSettingsTo(singularity)
  onSingularityChanged: pushSettingsTo(singularity)

  // serviceFor() is not reactive when the service finishes loading asynchronously.
  Timer {
    interval: 200
    repeat: true
    running: root.bar && root.bar.shell && !attached
    property bool attached: false
    onTriggered: {
      var svc = root.bar.shell.serviceFor("david.singularity")
      if (!svc) return
      root.pushSettingsTo(svc)
      attached = true
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: hasTasks ? "\uF046" : "\uF044"
    tooltipText: root.tooltip
    fontFamily: "JetBrainsMono Nerd Font"
    onPressed: function(b) {
      if (!root.bar || !root.bar.shell) return
      if (b === Qt.LeftButton) {
        root.bar.shell.summon("david.singularity", "{}")
      } else if (b === Qt.RightButton) {
        root.bar.shell.toggle("david.singularity", "{}")
      }
    }
  }
}
