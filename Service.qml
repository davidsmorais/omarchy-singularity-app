import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SingularityApp background service. Polls the v2 REST API and owns the task
// list, projects, and tags that the bar widget and panel read from.
//
// API: https://singularity-app.com/wiki/api/  (Bearer token in Authorization header)
// Base URL: https://api.singularity-app.com/v2
//
// Data model notes (verified against the live API):
//   - `start` is an ISO instant. Date-only tasks (`useTime: false`) are stored as
//     local midnight expressed in UTC, so every date/time here is read through
//     `new Date(task.start)` in the local timezone, never by slicing the string.
//   - `useTime` says whether the time-of-day is meaningful; `timeLength` is minutes.
//   - Completion is `checked` (0 open, 1 done, 2 cancelled); `complete` is a progress value.
Item {
	id: root

	readonly property string pluginId: "david.singularity"
	// Injected by the shell when the service instance is created.
	property var shell: null
	property var settings: ({ apiToken: "", refreshMinutes: 5, maxTasks: 50, showCompleted: "off" })
	property bool panelOpen: false
	property bool loading: false
	property string error: ""
	property var tasks: []
	property var projects: []
	property var tags: []
	property bool projectsLoaded: false
	property bool tagsLoaded: false

	// Derived views, rebuilt by rebuild(). All are sorted by due date/time.
	property var overdueTasks: []
	property var todayTasks: []
	property var undatedTasks: []
	property int todayCount: 0

	readonly property string baseUrl: "https://api.singularity-app.com/v2"
	readonly property int refreshMs: {
		var m = parseInt(String(settings.refreshMinutes || 5), 10)
		if (!isFinite(m) || m < 1) m = 5
		if (m > 60) m = 60
		return m * 60 * 1000
	}
	readonly property int maxTasks: parseInt(String(settings.maxTasks || 50), 10) || 50
	readonly property bool showCompleted: settings.showCompleted === "on"

	// Ticks every minute so "today" rolls over at midnight without a restart.
	property var now: new Date()
	readonly property string todayIso: isoDay(now)
	readonly property string tomorrowIso: isoDay(addDays(now, 1))

	onTasksChanged: rebuild()
	onNowChanged: rebuild()
	onSettingsChanged: rebuild()

	// ── Timers ────────────────────────────────────────────────────────────
	Timer {
		id: clockTimer
		interval: 60000
		repeat: true
		running: true
		onTriggered: root.now = new Date()
	}

	// Polls whenever a token is set so the bar count stays current even when
	// the panel is closed.
	Timer {
		id: pollTimer
		interval: root.refreshMs
		repeat: true
		triggeredOnStart: true
		running: root.settings.apiToken !== ""
		onTriggered: root.refresh()
	}

	Timer {
		id: dataTimer
		interval: 300000
		repeat: true
		triggeredOnStart: true
		running: root.settings.apiToken !== ""
		onTriggered: loadProjectsAndTags()
	}

	// ── Date helpers ──────────────────────────────────────────────────────
	function pad2(n) { return String(n).padStart(2, "0") }

	// Local calendar day as YYYY-MM-DD.
	function isoDay(d) {
		return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
	}

	function addDays(d, n) {
		var c = new Date(d.getTime())
		c.setDate(c.getDate() + n)
		return c
	}

	// "YYYY-MM-DD" + optional "HH:MM" -> local Date.
	function localDate(dayIso, timeStr) {
		var p = String(dayIso).split("-")
		var h = 0, m = 0
		if (timeStr) {
			var t = String(timeStr).split(":")
			h = parseInt(t[0], 10) || 0
			m = parseInt(t[1], 10) || 0
		}
		return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10), h, m, 0, 0)
	}

	function startDate(task) {
		if (!task || !task.start) return null
		var d = new Date(task.start)
		return isNaN(d.getTime()) ? null : d
	}

	// Local calendar day of a task's start, or "" when unscheduled.
	function dayKey(task) {
		var d = startDate(task)
		return d ? isoDay(d) : ""
	}

	function hasTime(task) {
		return !!task && task.useTime === true && startDate(task) !== null
	}

	// "HH:MM" local, or "" when the task has no time of day.
	function timeText(task) {
		if (!hasTime(task)) return ""
		var d = startDate(task)
		return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
	}

	function isDone(task) {
		if (!task) return false
		return task.checked === 1 || task.checked === 2 || !!task.journalDate || task.removed === true
	}

	function isOverdue(task) {
		if (!task || isDone(task)) return false
		var k = dayKey(task)
		return k !== "" && k < root.todayIso
	}

	// Earliest first; unscheduled last; ties broken by title.
	function compareTasks(a, b) {
		var da = startDate(a), db = startDate(b)
		if (da && !db) return -1
		if (!da && db) return 1
		if (da && db && da.getTime() !== db.getTime()) return da.getTime() - db.getTime()
		return String(a.title || "").localeCompare(String(b.title || ""))
	}

	function sortTasks(list) {
		var sorted = list.slice()
		sorted.sort(compareTasks)
		return sorted
	}

	// Kept for callers that still use the old name.
	function sortTodayTasks(list) { return sortTasks(list) }

	// ── Derived lists ─────────────────────────────────────────────────────
	function rebuild() {
		var overdue = [], today = [], undated = []
		var list = root.tasks || []
		for (var i = 0; i < list.length; i++) {
			var t = list[i]
			if (!t || t.removed === true || t.isNote === true) continue
			if (t.journalDate && t.journalDate !== "") continue
			var done = isDone(t)
			var key = dayKey(t)
			if (key === "") {
				if (!done) undated.push(t)
			} else if (done) {
				if (root.showCompleted && key === root.todayIso) today.push(t)
			} else if (key < root.todayIso) {
				overdue.push(t)
			} else if (key === root.todayIso) {
				today.push(t)
			}
		}
		overdue = sortTasks(overdue)
		today = sortTasks(today)
		undated = sortTasks(undated)
		var open = 0
		for (var j = 0; j < today.length; j++) if (!isDone(today[j])) open++
		root.todayCount = overdue.length + open
		// maxTasks caps what the list renders, most urgent first.
		var cap = root.maxTasks
		root.overdueTasks = overdue.slice(0, cap)
		root.todayTasks = today.slice(0, Math.max(0, cap - root.overdueTasks.length))
		root.undatedTasks = undated.slice(0, Math.max(0, cap - root.overdueTasks.length - root.todayTasks.length))
	}

	// Every non-removed task scheduled on a local day, sorted by start.
	function tasksForDay(dayIso) {
		var out = []
		var list = root.tasks || []
		for (var i = 0; i < list.length; i++) {
			var t = list[i]
			if (!t || t.removed === true || t.isNote === true) continue
			if (t.journalDate && t.journalDate !== "") continue
			if (dayKey(t) === dayIso) out.push(t)
		}
		return sortTasks(out)
	}

	// Open tasks that still need a slot: undated, overdue, or dated without a time.
	function tasksToSchedule(dayIso) {
		var out = []
		var list = root.tasks || []
		for (var i = 0; i < list.length; i++) {
			var t = list[i]
			if (!t || t.removed === true || t.isNote === true || isDone(t)) continue
			if (t.journalDate && t.journalDate !== "") continue
			var key = dayKey(t)
			if (key === "" || key < root.todayIso || (key === dayIso && !hasTime(t))) out.push(t)
		}
		return sortTasks(out)
	}

	// ── Public API ────────────────────────────────────────────────────────
	function refresh() {
		if (root.settings.apiToken === "") {
			root.tasks = []
			root.error = "No API token set. Enter one below."
			return
		}
		root.loading = true
		root.error = ""
		fetchTasks()
	}

	function openPanel() {
		root.panelOpen = true
		refresh()
	}

	function closePanel() {
		root.panelOpen = false
	}

	function togglePanel() {
		root.panelOpen = !root.panelOpen
	}

	// `root.shell.barConfig` (PluginShellApi.barConfig) is already the bar
	// section's content (`{ layout: { left, center, right } }`), not the
	// top-level shell config — it comes from the shell's own
	// `publicBarConfig()`, which returns `shell.barConfig` and that in turn
	// is already `shellConfig.bar`. Reading it as `cfg.bar.layout` (as if
	// `cfg` were the top-level config) or `cfg.plugins` (a top-level key
	// that `publicBarConfig()` never includes) never matches anything, so
	// this always returned null and every settings resync from the shell
	// silently no-opped — this was the actual "API token doesn't persist"
	// bug: saves wrote to disk fine, but nothing ever read them back in.
	function layoutEntryFromShell() {
		if (!root.shell || !root.shell.barConfig) return null
		var layout = root.shell.barConfig.layout
		if (!layout) return null
		var sections = ["left", "center", "right"]
		for (var s = 0; s < sections.length; s++) {
			var arr = layout[sections[s]] || []
			for (var i = 0; i < arr.length; i++) {
				var entry = arr[i]
				if (entry && String(entry.id || "") === root.pluginId) return entry
			}
		}
		return null
	}

	function normalizeShowCompleted(value) {
		if (value === true || value === "on") return "on"
		if (value === false || value === "off") return "off"
		return "off"
	}

	// Read inline bar settings from shell.json (via the live shell config).
	function syncSettingsFromShell() {
		var entry = layoutEntryFromShell()
		if (!entry) return false
		var next = {}
		for (var k in root.settings) next[k] = root.settings[k]
		if (entry.apiToken !== undefined && entry.apiToken !== null)
			next.apiToken = String(entry.apiToken)
		if (entry.refreshMinutes !== undefined && entry.refreshMinutes !== null)
			next.refreshMinutes = entry.refreshMinutes
		if (entry.maxTasks !== undefined && entry.maxTasks !== null)
			next.maxTasks = entry.maxTasks
		if (entry.showCompleted !== undefined && entry.showCompleted !== null)
			next.showCompleted = normalizeShowCompleted(entry.showCompleted)
		if (JSON.stringify(next) === JSON.stringify(root.settings)) return false
		root.settings = next
		return true
	}

	// Falls back to the CLI (the same path `omarchy bar set` uses) whenever
	// the shell-API write isn't available or throws, so a save never
	// silently no-ops just because the scoped shell object wasn't ready.
	// The API token is never handed to the CLI: argv is readable by every
	// local process (/proc/<pid>/cmdline). It goes to a 0600 file over stdin
	// instead, see writeTokenFile().
	function persistSettingEntry(entry) {
		if (root.shell && typeof root.shell.updateEntryInline === "function") {
			try {
				root.shell.updateEntryInline(root.pluginId, entry)
				return
			} catch (e) {
				console.warn("david.singularity: updateEntryInline failed, falling back to CLI:", e)
			}
		}
		for (var key in entry) {
			if (key === "id") continue
			if (key === "apiToken") {
				writeTokenFile(String(entry[key]))
				continue
			}
			Quickshell.execDetached(["omarchy", "bar", "set", root.pluginId, key, String(entry[key])])
		}
	}

	// ── Token file fallback ───────────────────────────────────────────────
	readonly property string tokenDir: {
		var state = Quickshell.env("XDG_STATE_HOME")
		if (!state) state = Quickshell.env("HOME") + "/.local/state"
		return state + "/omarchy/plugins/" + root.pluginId
	}
	readonly property string tokenFilePath: tokenDir + "/api-token"
	property string pendingTokenWrite: ""

	// The token travels over stdin only; the shell script creates the file
	// under umask 077 and renames it into place atomically.
	Process {
		id: tokenWriter
		stdinEnabled: true
		command: ["sh", "-c",
			"umask 077 && mkdir -p \"$1\" && cat > \"$1/api-token.tmp\" && mv -f \"$1/api-token.tmp\" \"$1/api-token\"",
			"sh", root.tokenDir]
		onStarted: {
			write(root.pendingTokenWrite)
			root.pendingTokenWrite = ""
			stdinEnabled = false
		}
		onExited: function(exitCode) {
			stdinEnabled = true
			if (exitCode !== 0) console.warn("david.singularity: failed to save API token file")
			// A newer token arrived while the previous write was in flight.
			if (root.pendingTokenWrite !== "") running = true
		}
	}

	function writeTokenFile(token) {
		root.pendingTokenWrite = token
		if (!tokenWriter.running) tokenWriter.running = true
	}

	FileView {
		id: tokenFile
		path: root.tokenFilePath
		printErrors: false
		onLoaded: {
			var t = String(text() || "").trim()
			if (t === "" || root.settings.apiToken !== "") return
			var next = {}
			for (var k in root.settings) next[k] = root.settings[k]
			next.apiToken = t
			root.settings = next
			root.loadProjectsAndTags()
			root.refresh()
		}
	}

	function saveApiToken(token) {
		var t = String(token || "").trim()
		if (t === "") return
		saveSetting("apiToken", t)
	}

	// Persists to shell.json through the shell API (same path as omarchy bar set).
	function saveSetting(key, value) {
		var v = String(value === undefined || value === null ? "" : value)
		var next = {}
		for (var k in root.settings) next[k] = root.settings[k]
		next[key] = v
		var entry = { id: root.pluginId }
		for (var ek in next) if (ek !== "id") entry[ek] = next[ek]
		persistSettingEntry(entry)
		root.settings = next
		if (key === "apiToken") {
			if (v !== "") loadProjectsAndTags()
			refresh()
		}
	}

	// ── Fetch ─────────────────────────────────────────────────────────────
	function fetchTasks() {
		// One request for everything: the API returns all tasks (no server-side
		// due-date ordering), so filtering and sorting happen locally.
		var fetch = http("GET", "/task?includeRemoved=false&includeArchived=false&maxCount=1000")
		fetch(function(ok, data, err) {
			root.loading = false
			if (!ok) {
				root.error = err || "Failed to load tasks"
				return
			}
			root.tasks = Array.isArray(data && data.tasks) ? data.tasks : (Array.isArray(data) ? data : [])
			root.error = ""
		})
	}

	function loadProjectsAndTags() {
		if (root.settings.apiToken === "") return
		http("GET", "/project?maxCount=100")(function(ok, data, err) {
			if (ok) {
				root.projects = Array.isArray(data && data.projects) ? data.projects : []
				root.projectsLoaded = true
			}
		})
		http("GET", "/tag?maxCount=200")(function(ok, data, err) {
			if (ok) {
				root.tags = Array.isArray(data && data.tags) ? data.tags.filter(function(t) { return !t.removed }) : []
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
		http("POST", "/task", body)(function(ok, data, err) {
			if (!ok) {
				root.error = "Failed to create task: " + (err || "unknown error")
				return
			}
			refresh()
		})
	}

	// startDate is "YYYY-MM-DD" (local) or ""; time is "HH:MM" (local) or "".
	function addTask(title, note, priority, startDate, projectId, tags, time) {
		if (!title || title.trim() === "") {
			root.error = "Task title is required"
			return
		}
		var body = { title: title.trim() }
		if (note !== undefined && note !== null && note.trim() !== "") body.note = note.trim()
		if (priority !== undefined && priority !== null) body.priority = priority
		var day = startDate ? String(startDate).trim().slice(0, 10) : ""
		if (day !== "") {
			var s = startFields(day, time)
			body.start = s.start
			body.useTime = s.useTime
			if (s.useTime) body.timeLength = 60
		}
		if (projectId !== undefined && projectId !== null && projectId !== "") body.projectId = projectId
		if (tags !== undefined && tags !== null && tags.length > 0) body.tags = tags
		createTask(body)
	}

	// Body fields for placing a task on a local day, optionally at a local time.
	function startFields(dayIso, timeStr) {
		var d = localDate(dayIso, timeStr)
		return { start: d.toISOString(), useTime: !!timeStr }
	}

	function completeTask(taskId) {
		if (root.settings.apiToken === "") return
		patchTask(taskId, { checked: 1 })
	}

	function uncompleteTask(taskId) {
		if (root.settings.apiToken === "") return
		patchTask(taskId, { checked: 0 })
	}

	function cancelTask(taskId) {
		if (root.settings.apiToken === "") return
		patchTask(taskId, { checked: 2 })
	}

	function findTask(taskId) {
		var list = root.tasks || []
		for (var i = 0; i < list.length; i++) if (list[i].id === taskId) return list[i]
		return null
	}

	// Moves a task to tomorrow, keeping its time of day if it has one.
	function postponeTask(taskId) {
		if (root.settings.apiToken === "") return
		var t = findTask(taskId)
		var time = t ? timeText(t) : ""
		var body = startFields(root.tomorrowIso, time)
		if (!body.useTime) body.timeLength = 0
		patchTask(taskId, body)
	}

	// Places a task in a 1-hour block: `hour` (0-23) on local `dayIso`.
	// Existing durations are kept; tasks without one get 60 minutes.
	function scheduleAt(taskId, dayIso, hour) {
		if (root.settings.apiToken === "") return
		var t = findTask(taskId)
		var len = t && t.timeLength > 0 ? t.timeLength : 60
		var body = startFields(dayIso, pad2(hour) + ":00")
		body.timeLength = len
		patchTask(taskId, body)
	}

	// timeStr "HH:MM" schedules today at that time; "" clears the time.
	function scheduleForToday(taskId, timeStr) {
		if (root.settings.apiToken === "") return
		if (!timeStr) {
			var body = startFields(root.todayIso, "")
			body.timeLength = 0
			patchTask(taskId, body)
			return
		}
		var t = findTask(taskId)
		var b = startFields(root.todayIso, timeStr)
		b.timeLength = t && t.timeLength > 0 ? t.timeLength : 60
		patchTask(taskId, b)
	}

	// Applies a PATCH locally first so the UI reacts instantly, then confirms
	// with the server (refreshing on failure to roll back).
	function patchTask(taskId, body) {
		var list = (root.tasks || []).map(function(t) {
			if (t.id !== taskId) return t
			var c = {}
			for (var k in t) c[k] = t[k]
			for (var f in body) c[f] = body[f]
			return c
		})
		root.tasks = list
		http("PATCH", "/task/" + encodeURIComponent(taskId), body)(function(ok, data, err) {
			if (!ok) root.error = "Failed to update task: " + (err || "unknown error")
			refresh()
		})
	}

	function deleteTask(taskId) {
		if (root.settings.apiToken === "") return
		root.tasks = (root.tasks || []).filter(function(t) { return t.id !== taskId })
		http("DELETE", "/task/" + encodeURIComponent(taskId))(function(ok, data, err) {
			if (!ok) root.error = "Failed to delete task: " + (err || "unknown error")
			refresh()
		})
	}

	// ── HTTP helper ───────────────────────────────────────────────────────
	// Requests run through curl rather than XMLHttpRequest, because QML's XHR
	// has no deadline and buffers the whole body before we can look at it.
	//   - Deadline: curl --connect-timeout/--max-time, plus a watchdog Timer
	//     that kills the process if curl itself hangs.
	//   - Size cap: the body is piped through `head -c`, so at most
	//     maxResponseBytes (+ a few bytes for the status line) ever reach the
	//     shell; anything larger makes curl die on SIGPIPE and is rejected.
	//   - The token and request body are passed via `curl -K -` on stdin, so
	//     they never appear in argv.
	readonly property int requestTimeoutSec: 20
	readonly property int maxResponseBytes: 4 * 1024 * 1024
	readonly property string statusMarker: "\n__SINGULARITY_HTTP_STATUS__:"

	Component {
		id: requestComponent
		Process {
			id: proc
			property string config: ""
			property var done: null
			property bool finished: false
			property bool timedOut: false

			stdinEnabled: true
			command: ["bash", "-c",
				"set -o pipefail; curl --silent --show-error --proto =https --max-redirs 0 " +
				"--connect-timeout 10 --max-time \"$1\" --config - " +
				"--write-out \"$2%{http_code}\" | head -c \"$3\"",
				"bash", String(root.requestTimeoutSec), root.statusMarker,
				String(root.maxResponseBytes + root.statusMarker.length + 3)]
			stdout: StdioCollector { id: out }
			stderr: StdioCollector { id: err }

			onStarted: {
				write(config)
				config = ""
				stdinEnabled = false
			}
			onExited: function(exitCode) {
				if (finished) return
				finished = true
				watchdog.stop()
				// Collectors flush on stream end; read them on the next tick.
				Qt.callLater(function() {
					var cb = proc.done
					var stdoutText = out.text
					var stderrText = err.text
					proc.destroy()
					root.finishRequest(cb, exitCode, stdoutText, stderrText, proc.timedOut)
				})
			}

			property Timer watchdog: Timer {
				interval: (root.requestTimeoutSec + 5) * 1000
				running: true
				onTriggered: {
					proc.timedOut = true
					proc.signal(9)
				}
			}
		}
	}

	function curlQuote(v) {
		return "\"" + String(v).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
			.replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + "\""
	}

	function finishRequest(callback, exitCode, stdoutText, stderrText, timedOut) {
		if (timedOut || exitCode === 28) {
			callback(false, null, "Request timed out: SingularityApp API did not respond in time")
			return
		}
		var idx = stdoutText.lastIndexOf(root.statusMarker)
		var status = idx >= 0 ? parseInt(stdoutText.slice(idx + root.statusMarker.length), 10) : NaN
		var body = idx >= 0 ? stdoutText.slice(0, idx) : stdoutText
		if (body.length > root.maxResponseBytes || (idx < 0 && stdoutText.length >= root.maxResponseBytes)) {
			callback(false, null, "Response too large from SingularityApp API")
			return
		}
		if (exitCode !== 0 || !isFinite(status) || status === 0) {
			console.warn("david.singularity: request failed:", exitCode, stderrText.trim())
			callback(false, null, "Network error: could not reach SingularityApp API")
			return
		}
		if (status >= 200 && status < 300) {
			var data = null
			try { data = body === "" ? null : JSON.parse(body) } catch (e) { data = body }
			callback(true, data, "")
		} else {
			var msg = "API error " + status
			try {
				var errBody = JSON.parse(body)
				if (errBody && errBody.message) msg = errBody.message
				else if (errBody && errBody.error) msg = errBody.error
			} catch (e) { /* use status code */ }
			callback(false, null, msg)
		}
	}

	function http(method, path, body) {
		return function(callback) {
			var lines = [
				"url = " + curlQuote(root.baseUrl + path),
				"request = " + curlQuote(method),
				"header = " + curlQuote("Authorization: Bearer " + root.settings.apiToken),
				"header = " + curlQuote("Content-Type: application/json")
			]
			if (body !== undefined && body !== null)
				lines.push("data-binary = " + curlQuote(JSON.stringify(body)))
			var proc = requestComponent.createObject(root, { config: lines.join("\n") + "\n", done: callback })
			if (!proc) {
				callback(false, null, "Could not start request")
				return
			}
			proc.running = true
		}
	}

	function ping() { return "ok" }

	Connections {
		target: root.shell
		function onBarConfigChanged() {
			if (root.syncSettingsFromShell() && root.settings.apiToken !== "") {
				root.loadProjectsAndTags()
				root.refresh()
			}
		}
	}

	// The shell injects `shell` on this instance right after createObject(),
	// which is *after* Component.onCompleted already ran (onCompleted fires
	// synchronously inside createObject(), before the caller can assign
	// properties on the result). So the Component.onCompleted sync below
	// always finds `shell` still null and silently no-ops, and nothing
	// else re-triggers it since Connections.onBarConfigChanged only fires
	// on later *changes*, not on the initial assignment of its target.
	// Without this handler the token in shell.json is simply never read
	// into `settings`, which is why the panel would sit on "Loading…"
	// forever even with a token configured. Re-sync as soon as `shell`
	// itself arrives.
	onShellChanged: {
		if (root.syncSettingsFromShell() && root.settings.apiToken !== "") {
			root.loadProjectsAndTags()
			root.refresh()
		}
	}

	Component.onCompleted: {
		root.syncSettingsFromShell()
		if (root.settings.apiToken !== "") {
			loadProjectsAndTags()
			refresh()
		}
	}
}
