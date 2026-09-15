import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SingularityApp background service. Polls the v2 REST API and owns the task
// list, projects, and tags that the bar widget and panel read from.
//
// API: https://api.singularity-app.com/v2/api  (Bearer token in Authorization header)
// Base URL: https://api.singularity-app.com/v2
Item {
  id: root

  readonly property string pluginId: "david.singularity"
  property var settings: ({ apiToken: "", refreshMinutes: 5, maxTasks: 50 })
  property bool panelOpen: false
  property bool loading: false
  property string error: ""
  property var tasks: []
  property var todayTasks: []
  property var projects: []
  property var tags: []
  property int todayCount: 0
  property bool projectsLoaded: false
  property bool tagsLoaded: false

  readonly property string baseUrl: "https://api.singularity-app.com/v2"
  readonly property int refreshMs: {
    var m = parseInt(String(settings.refreshMinutes || 5), 10)
    if (!isFinite(m) || m < 1) m = 5
    if (m > 60) m = 60
    return m * 60 * 1000
  }

  // Today's date in ISO format (YYYY-MM-DD) for filtering and scheduling
  readonly property string todayIso: {
    var d = new Date()
    var y = d.getFullYear()
    var m = String(d.getMonth() + 1).padStart(2, "0")
    var day = String(d.getDate()).padStart(2, "0")
    return y + "-" + m + "-" + day
  }

  // Tomorrow's date in ISO format
  readonly property string tomorrowIso: {
    var d = new Date()
    d.setDate(d.getDate() + 1)
    var y = d.getFullYear()
    var m = String(d.getMonth() + 1).padStart(2, "0")
    var day = String(d.getDate()).padStart(2, "0")
    return y + "-" + m + "-" + day
  }

  // ── Timer-based polling ──────────────────────────────────────────────
  Timer {
    id: pollTimer
    interval: root.refreshMs
    repeat: true
    triggeredOnStart: true
    running: root.settings.apiToken !== "" && root.panelOpen
    onTriggered: root.refresh()
  }

  Timer {
    id: dataTimer
    interval: 60000  // 1 minute
    repeat: true
    triggeredOnStart: true
    running: root.settings.apiToken !== ""
    onTriggered: loadProjectsAndTags()
  }

  // ── Public API ────────────────────────────────────────────────────────
  function refresh() {
    if (root.settings.apiToken === "") {
      root.tasks = []
      root.todayTasks = []
      root.todayCount = 0
      root.error = "No API token set. Enter one below."
      return
    }
    root.loading = true
    root.error = ""
    fetchTasks()
  }

  function openPanel() {
    root.panelOpen = true
    if (!pollTimer.running) pollTimer.restart()
    if (!dataTimer.running) dataTimer.restart()
  }

  function closePanel() {
    root.panelOpen = false
  }

  function togglePanel() {
    if (root.panelOpen) root.panelOpen = false
    else root.panelOpen = true
  }

  // Applies the token immediately for this session and persists it via the
  // official CLI so it survives a shell restart. Plugins can't write
  // shell.json directly — `omarchy bar set` is the supported path.
  function saveApiToken(token) {
    var t = String(token || "").trim()
    if (t === "") return
    var next = {}
    for (var k in root.settings) next[k] = root.settings[k]
    next.apiToken = t
    root.settings = next
    Quickshell.execDetached(["omarchy", "bar", "set", root.pluginId, "apiToken", t])
    loadProjectsAndTags()
    refresh()
  }

  // ── Task filtering ────────────────────────────────────────────────────
  function isTodayTask(task) {
    if (!task) return false
    if (task.complete === 1 || task.removed === true) return false
    if (task.journalDate && task.journalDate !== "") return false
    // Task is for today if it's overdue, due today, or has no start date (unscheduled)
    if (!task.start || task.start === "") return true
    var taskDate = task.start.slice(0, 10)
    return taskDate <= root.todayIso
  }

  function filterTodayTasks(allTasks) {
    return allTasks.filter(isTodayTask)
  }

  // ── Fetch tasks ───────────────────────────────────────────────────────
  function fetchTasks() {
    var params = []
    params.push("includeRemoved=false")
    params.push("includeArchived=false")
    params.push("maxCount=" + root.settings.maxTasks)
    var query = "?" + params.join("&")
    var fetch = http("GET", "/task" + query)
    fetch(function(ok, data, err) {
      root.loading = false
      if (!ok) {
        root.error = err || "Failed to load tasks"
        root.tasks = []
        root.todayTasks = []
        root.todayCount = 0
        return
      }
      var list = Array.isArray(data.tasks) ? data.tasks : (Array.isArray(data) ? data : [])
      root.tasks = list
      root.todayTasks = filterTodayTasks(list)
      root.todayCount = root.todayTasks.length
      root.error = ""
    })
  }

  // ── Load projects and tags ────────────────────────────────────────────
  function loadProjectsAndTags() {
    if (root.settings.apiToken === "") return
    // Load both in parallel
    var pFetch = http("GET", "/project?maxCount=100")
    var tFetch = http("GET", "/tag?maxCount=200")
    pFetch(function(ok, data, err) {
      if (ok) {
        root.projects = Array.isArray(data.projects) ? data.projects : []
        root.projectsLoaded = true
      }
    })
    tFetch(function(ok, data, err) {
      if (ok) {
        root.tags = Array.isArray(data.tags) ? data.tags.filter(function(t) { return !t.removed }) : []
        root.tagsLoaded = true
      }
    })
  }

  // ── Task CRUD ─────────────────────────────────────────────────────────
  function createTask(body) {
    if (root.settings.apiToken === "") {
      root.error = "No API token set"
      return
    }
    var create = http("POST", "/task", body)
    create(function(ok, data, err) {
      if (!ok) {
        root.error = "Failed to create task: " + (err || "unknown error")
        return
      }
      refresh()
    })
  }

  function addTask(title, note, priority, startDate, projectId, tags) {
    if (!title || title.trim() === "") {
      root.error = "Task title is required"
      return
    }
    var body = { title: title.trim() }
    if (note !== undefined && note !== null && note.trim() !== "") body.note = note.trim()
    if (priority !== undefined && priority !== null) body.priority = priority
    if (startDate !== undefined && startDate !== null && startDate.trim() !== "") {
      // Ensure ISO format with time
      var d = new Date(startDate)
      if (!isNaN(d)) {
        body.start = d.toISOString()
      } else {
        // Assume it's already a date string, add midnight UTC
        body.start = startDate.trim() + "T00:00:00.000Z"
      }
    }
    if (projectId !== undefined && projectId !== null && projectId !== "") body.projectId = projectId
    if (tags !== undefined && tags !== null && tags.length > 0) body.tags = tags
    createTask(body)
  }

  function completeTask(taskId) {
    if (root.settings.apiToken === "") return
    patchTask(taskId, { complete: 1 })
  }

  function uncompleteTask(taskId) {
    if (root.settings.apiToken === "") return
    patchTask(taskId, { complete: 0 })
  }

  function postponeTask(taskId) {
    if (root.settings.apiToken === "") return
    // Set start to tomorrow at the same time, or tomorrow midnight if no time
    patchTask(taskId, { start: root.tomorrowIso + "T00:00:00.000Z" })
  }

  function scheduleForToday(taskId, timeStr) {
    if (root.settings.apiToken === "") return
    // timeStr is like "14:30" — build today's ISO with that time
    var iso = root.todayIso + "T" + timeStr + ":00.000Z"
    patchTask(taskId, { start: iso })
  }

  function cancelTask(taskId) {
    if (root.settings.apiToken === "") return
    // Move to trash by setting deleteDate to today
    patchTask(taskId, { deleteDate: root.todayIso })
  }

  function patchTask(taskId, body) {
    var patch = http("PATCH", "/task/" + encodeURIComponent(taskId), body)
    patch(function(ok, data, err) {
      if (!ok) {
        root.error = "Failed to update task: " + (err || "unknown error")
      } else {
        refresh()
      }
    })
  }

  function deleteTask(taskId) {
    if (root.settings.apiToken === "") return
    deleteViaApi("/task/" + encodeURIComponent(taskId))
  }

  function deleteViaApi(path) {
    var del = http("DELETE", path)
    del(function(ok, data, err) {
      if (!ok) {
        root.error = "Failed to delete task: " + (err || "unknown error")
      } else {
        refresh()
      }
    })
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────
  function http(method, path, body) {
    return function(callback) {
      var xhr = new XMLHttpRequest()
      var url = root.baseUrl + path
      xhr.open(method, url, true)
      xhr.setRequestHeader("Authorization", "Bearer " + root.settings.apiToken)
      xhr.setRequestHeader("Content-Type", "application/json")
      if (body !== undefined && body !== null) {
        xhr.setRequestHeader("Content-Type", "application/json")
      }
      xhr.onerror = function() { callback(false, null, "Network error: could not reach SingularityApp API") }
      xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
          var data = null
          try { data = JSON.parse(xhr.responseText) } catch (e) { data = xhr.responseText }
          callback(true, data, "")
        } else {
          var msg = "API error " + xhr.status
          try {
            var errBody = JSON.parse(xhr.responseText)
            if (errBody && errBody.message) msg = errBody.message
            else if (errBody && errBody.error) msg = errBody.error
          } catch (e) { /* use status text */ }
          callback(false, null, msg)
        }
      }
      if (body !== undefined && body !== null) {
        xhr.send(JSON.stringify(body))
      } else {
        xhr.send()
      }
    }
  }

  // ── Task sorting ──────────────────────────────────────────────────────
  function sortTodayTasks(tasks) {
    // Sort: unscheduled first (no start), then by time
    var sorted = tasks.slice()
    sorted.sort(function(a, b) {
      var aHasStart = a.start && a.start !== ""
      var bHasStart = b.start && b.start !== ""
      if (aHasStart && !bHasStart) return 1
      if (!aHasStart && bHasStart) return -1
      if (!aHasStart && !bHasStart) return 0
      // Both have start — compare by time
      var aTime = a.start.slice(11, 16)
      var bTime = b.start.slice(11, 16)
      return aTime.localeCompare(bTime)
    })
    return sorted
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────
  function ping() { return "ok" }

  Component.onCompleted: {
    // Don't auto-poll until the panel is opened (on-demand activation).
    // Load projects and tags immediately so they're ready when the panel opens.
    if (root.settings.apiToken !== "") {
      loadProjectsAndTags()
    }
  }
}
