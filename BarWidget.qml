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

  property bool loading: false
  property string error: ""
  property bool hasToken: (settings.apiToken || "") !== ""

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

  onSettingsChanged: {
    if (singularity) singularity.settings = normalizedSettings()
    if (hasToken) {
      error = ""
      if (singularity) singularity.refresh()
    }
  }

  onSingularityChanged: {
    if (singularity) {
      singularity.settings = normalizedSettings()
      loading = singularity.loading
      error = singularity.error
      if (hasToken) singularity.refresh()
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
