import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// SingularityApp service entry: the shell owns one instance of this per plugin.
// The bar widget reads today's task count from the service; the panel talks to it directly.
Item {
  id: root

  readonly property string pluginId: "david.singularity"

  signal openPanelRequested()
  signal closePanelRequested()
  signal togglePanelRequested()
  signal refreshRequested()
  signal addTaskRequested(string title, string note, int priority, string startDate, string projectId, var tags)
  signal completeTaskRequested(string taskId)
  signal uncompleteTaskRequested(string taskId)
  signal postponeTaskRequested(string taskId)
  signal cancelTaskRequested(string taskId)
  signal scheduleTaskRequested(string taskId, string timeValue)
  signal deleteTaskRequested(string taskId)

  // Delegate everything to the actual service instance once the shell injects it.
  property var service: null

  function openPanel() { if (service) service.openPanel() }
  function closePanel() { if (service) service.closePanel() }
  function togglePanel() { if (service) service.togglePanel() }
  function refresh() { if (service) service.refresh() }
  function addTask(title, note, priority, startDate, projectId, tags) { if (service) service.addTask(title, note, priority, startDate, projectId, tags) }
  function completeTask(taskId) { if (service) service.completeTask(taskId) }
  function uncompleteTask(taskId) { if (service) service.uncompleteTask(taskId) }
  function postponeTask(taskId) { if (service) service.postponeTask(taskId) }
  function cancelTask(taskId) { if (service) service.cancelTask(taskId) }
  function scheduleTask(taskId, timeValue) { if (service) service.scheduleForToday(taskId, timeValue) }
  function deleteTask(taskId) { if (service) service.deleteTask(taskId) }

  function ping() { return "ok" }
}
