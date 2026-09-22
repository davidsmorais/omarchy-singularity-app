import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// SingularityApp panel for Omarchy.
//   List tab   - overdue / today / undated tasks, sorted by due date and time,
//                every row showing its date. Quick add, complete, postpone, etc.
//   Agenda tab - a day timeline. Drag a task from "To schedule" (or move an
//                existing block) onto an hour to set its due date and hour in
//                SingularityApp as a 1-hour block.
//
// Summon with:  omarchy-shell shell summon david.singularity '{}'
//               omarchy-shell shell summon david.singularity '{"tab":"agenda"}'
Item {
	id: root

	property var bar: null
	property var shell: null
	property var service: null
	property var manifest: null

	readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "david.singularity"

	// ── Panel state ───────────────────────────────────────────────────────
	property bool opened: false
	property string tab: "list"
	property bool addingTask: false
	property string newTitle: ""
	property string newNote: ""
	property int newPriority: 1
	property string newDay: "today"   // today | tomorrow | none
	property string newTime: ""
	property string newProjectId: ""
	property var newTags: []
	property string panelError: ""
	property string panelSuccess: ""
	property string tokenInput: ""

	// List tab: which row is expanded, and which row shows the time picker.
	property string expandedTaskId: ""
	property string timePickerTaskId: ""

	// Agenda tab
	readonly property real hourHeight: 52
	readonly property real gutterWidth: 52
	property string agendaDay: ""
	property var dragTask: null
	property bool dragging: false
	property real dragX: 0
	property real dragY: 0
	property int hoverHour: -1
	property int autoScroll: 0

	// Time presets for scheduling (value "" means "no time").
	readonly property var timePresets: {
		var out = []
		for (var h = 6; h <= 22; h++) {
			var s = (h < 10 ? "0" : "") + h + ":00"
			out.push({ label: s, value: s })
		}
		return out
	}
	readonly property var timeOptions: [{ label: "No time", value: "" }].concat(timePresets)

	// ── Settings popup ────────────────────────────────────────────────────
	property bool showSettings: false
	property string settingToken: ""
	property int settingRefreshMinutes: 5
	property int settingMaxTasks: 50
	property string settingShowCompleted: "off"

	function syncSettingsToControls() {
		if (!service) return
		root.settingToken = service.settings.apiToken || ""
		root.settingRefreshMinutes = parseInt(String(service.settings.refreshMinutes || 5), 10) || 5
		root.settingMaxTasks = parseInt(String(service.settings.maxTasks || 50), 10) || 50
		var sc = service.settings.showCompleted
		root.settingShowCompleted = (sc === "on" || sc === "off") ? sc : "off"
	}

	function saveAllSettings() {
		if (!service) return
		if (root.settingToken !== service.settings.apiToken) service.saveSetting("apiToken", root.settingToken)
		if (root.settingRefreshMinutes !== parseInt(String(service.settings.refreshMinutes || 5), 10))
			service.saveSetting("refreshMinutes", String(root.settingRefreshMinutes))
		if (root.settingMaxTasks !== parseInt(String(service.settings.maxTasks || 50), 10))
			service.saveSetting("maxTasks", String(root.settingMaxTasks))
		if (root.settingShowCompleted !== (service.settings.showCompleted || "off"))
			service.saveSetting("showCompleted", root.settingShowCompleted)
		root.showSettings = false
	}

	// ── Theme ─────────────────────────────────────────────────────────────
	readonly property color themeBg: Color.background
	readonly property color themeFg: Color.foreground
	readonly property color themeAccent: Color.accent
	readonly property color themeMuted: Color.muted
	readonly property color themeUrgent: Color.urgent
	readonly property color surfaceBg: Qt.rgba(themeBg.r, themeBg.g, themeBg.b, 0.96)
	readonly property color lineColor: Qt.rgba(themeFg.r, themeFg.g, themeFg.b, 0.14)
	readonly property string fontFamily: {
		var families = Qt.fontFamilies()
		if (families.indexOf("JetBrains Mono") >= 0) return "JetBrains Mono"
		if (families.indexOf("JetBrainsMono Nerd Font") >= 0) return "JetBrainsMono Nerd Font"
		return families[0] || "sans-serif"
	}

	readonly property string todayDisplay: Qt.formatDate(service ? service.now : new Date(), "dddd, d MMMM")

	// ── Task helpers ──────────────────────────────────────────────────────
	function safeColor(c, fallback) {
		return (typeof c === "string" && /^#[0-9a-fA-F]{3,8}$/.test(c)) ? c : fallback
	}

	function getTaskProject(task) {
		if (!task || !task.projectId || !service) return null
		for (var i = 0; i < service.projects.length; i++) {
			if (service.projects[i].id === task.projectId) return service.projects[i]
		}
		return null
	}

	function projectColor(task) {
		var p = getTaskProject(task)
		return p ? safeColor(p.color, themeAccent) : themeAccent
	}

	function getTaskTags(task) {
		if (!task || !task.tags || !service) return []
		var result = []
		for (var i = 0; i < task.tags.length; i++) {
			for (var j = 0; j < service.tags.length; j++) {
				if (service.tags[j].id === task.tags[i]) {
					result.push(service.tags[j])
					break
				}
			}
		}
		return result
	}

	function priorityColor(p) {
		if (p === 0) return themeUrgent
		if (p === 2) return themeAccent
		return themeMuted
	}

	function isDone(task) { return service ? service.isDone(task) : false }
	function isOverdue(task) { return service ? service.isOverdue(task) : false }

	function dayText(key) {
		if (!service) return key
		if (key === service.todayIso) return "Today"
		if (key === service.tomorrowIso) return "Tomorrow"
		var d = service.localDate(key)
		var sameYear = d.getFullYear() === service.now.getFullYear()
		return Qt.formatDate(d, sameYear ? "ddd d MMM" : "d MMM yyyy")
	}

	// "Overdue · Tue 15 Sep · 09:00", "Today · 14:30", "Tomorrow", "No date"
	function dueLabel(task) {
		if (!service) return ""
		var key = service.dayKey(task)
		if (key === "") return "No date"
		var s = dayText(key)
		if (service.hasTime(task)) {
			s += " · " + service.timeText(task)
			if (task.timeLength > 0) s += "–" + endTimeText(task)
		}
		if (isOverdue(task)) s = "Overdue · " + s
		return s
	}

	function endTimeText(task) {
		var d = service.startDate(task)
		var e = new Date(d.getTime() + task.timeLength * 60000)
		return service.pad2(e.getHours()) + ":" + service.pad2(e.getMinutes())
	}

	function dueColor(task) {
		if (isOverdue(task)) return themeUrgent
		if (service && service.dayKey(task) === "") return themeMuted
		return themeMuted
	}

	// ── Panel lifecycle ───────────────────────────────────────────────────
	function openPanel() {
		opened = true
		if (service) service.openPanel()
	}

	function close() {
		opened = false
		dragCancel()
		if (service) service.closePanel()
	}

	function togglePanel() {
		if (opened) close()
		else openPanel()
	}

	// Called by the shell on `omarchy-shell shell summon david.singularity '{}'`
	function open(payloadJson) {
		var payload = ({})
		try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
		if (payload.tab === "agenda" || payload.tab === "list") root.tab = payload.tab
		openPanel()
	}

	function refresh() {
		if (service) service.refresh()
		panelError = ""
		panelSuccess = ""
	}

	// ── Add task ──────────────────────────────────────────────────────────
	function cancelAdd() {
		addingTask = false
		panelError = ""
	}

	function addTask() {
		var title = newTitle.trim()
		if (!title) { panelError = "Task title is required"; return }
		if (!service) return
		panelError = ""
		panelSuccess = ""
		var day = newDay === "today" ? service.todayIso : (newDay === "tomorrow" ? service.tomorrowIso : "")
		service.addTask(title, newNote, newPriority, day, newProjectId || "",
			newTags ? newTags.slice() : [], day !== "" ? newTime : "")
		newTitle = ""
		newNote = ""
		newPriority = 1
		newDay = "today"
		newTime = ""
		newProjectId = ""
		newTags = []
		addingTask = false
	}

	// ── Task actions ──────────────────────────────────────────────────────
	function completeTask(taskId) {
		if (service) service.completeTask(taskId)
		panelError = ""
		expandedTaskId = ""
	}

	function uncompleteTask(taskId) {
		if (service) service.uncompleteTask(taskId)
		panelError = ""
		expandedTaskId = ""
	}

	function postponeTask(taskId) {
		if (service) service.postponeTask(taskId)
		panelError = ""
		panelSuccess = "Postponed to tomorrow"
		expandedTaskId = ""
	}

	function cancelTask(taskId) {
		if (service) service.cancelTask(taskId)
		panelError = ""
		panelSuccess = "Task cancelled"
		expandedTaskId = ""
	}

	function scheduleTask(taskId, timeValue) {
		if (service) service.scheduleForToday(taskId, timeValue)
		panelError = ""
		expandedTaskId = ""
		timePickerTaskId = ""
	}

	function deleteTask(taskId) {
		if (service) service.deleteTask(taskId)
		panelError = ""
		expandedTaskId = ""
	}

	function expandTask(taskId) {
		expandedTaskId = expandedTaskId === taskId ? "" : taskId
		timePickerTaskId = ""
	}

	// ── Agenda ────────────────────────────────────────────────────────────
	readonly property string currentAgendaDay: agendaDay !== "" ? agendaDay : (service ? service.todayIso : "")

	function shiftAgendaDay(n) {
		if (!service) return
		agendaDay = service.isoDay(service.addDays(service.localDate(currentAgendaDay), n))
		Qt.callLater(scrollAgendaToDefault)
	}

	function goToToday() {
		agendaDay = ""
		Qt.callLater(scrollAgendaToDefault)
	}

	function scrollAgendaToDefault() {
		if (!service) return
		var hour = currentAgendaDay === service.todayIso ? Math.max(0, service.now.getHours() - 1) : 7
		agendaFlick.contentY = Math.max(0, Math.min(agendaFlick.contentHeight - agendaFlick.height, hour * hourHeight))
	}

	// Timed tasks of the selected day laid out in side-by-side lanes when they overlap.
	readonly property var agendaBlocks: {
		if (!service) return []
		var timed = service.tasksForDay(currentAgendaDay).filter(function(t) { return service.hasTime(t) })
		var items = timed.map(function(t) {
			var d = service.startDate(t)
			var s = d.getHours() * 60 + d.getMinutes()
			var len = Math.max(30, t.timeLength > 0 ? t.timeLength : 60)
			return { task: t, start: s, end: Math.min(24 * 60, s + len), lane: 0, lanes: 1 }
		})
		items.sort(function(a, b) { return a.start - b.start })
		var cluster = [], laneEnds = [], clusterEnd = -1
		function flush() {
			for (var k = 0; k < cluster.length; k++) cluster[k].lanes = laneEnds.length
			cluster = []; laneEnds = []
		}
		for (var i = 0; i < items.length; i++) {
			var it = items[i]
			if (cluster.length > 0 && it.start >= clusterEnd) flush()
			var lane = 0
			while (lane < laneEnds.length && laneEnds[lane] > it.start) lane++
			laneEnds[lane] = it.end
			it.lane = lane
			clusterEnd = cluster.length === 0 ? it.end : Math.max(clusterEnd, it.end)
			cluster.push(it)
		}
		flush()
		return items
	}

	readonly property var scheduleQueue: service ? service.tasksToSchedule(currentAgendaDay) : []

	// Drag and drop is hit-tested against the timeline geometry rather than
	// using DropAreas, so it behaves the same for sidebar chips and blocks.
	function dragMove(task, pt) {
		dragTask = task
		dragging = true
		dragX = pt.x
		dragY = pt.y
		updateHover()
	}

	function updateHover() {
		var q = dragLayer.mapToItem(agendaFlick, dragX, dragY)
		if (tab === "agenda" && q.x >= 0 && q.x <= agendaFlick.width && q.y >= 0 && q.y <= agendaFlick.height) {
			hoverHour = Math.max(0, Math.min(23, Math.floor((q.y + agendaFlick.contentY) / hourHeight)))
			autoScroll = q.y < 28 ? -1 : (q.y > agendaFlick.height - 28 ? 1 : 0)
		} else {
			hoverHour = -1
			autoScroll = 0
		}
	}

	function dragDrop() {
		if (dragging && dragTask && hoverHour >= 0 && service) {
			service.scheduleAt(dragTask.id, currentAgendaDay, hoverHour)
			panelSuccess = "Scheduled for " + dayText(currentAgendaDay) + " at " + service.pad2(hoverHour) + ":00"
		}
		dragCancel()
	}

	function dragCancel() {
		dragging = false
		dragTask = null
		hoverHour = -1
		autoScroll = 0
	}

	Timer {
		interval: 30
		repeat: true
		running: root.dragging && root.autoScroll !== 0
		onTriggered: {
			var max = Math.max(0, agendaFlick.contentHeight - agendaFlick.height)
			agendaFlick.contentY = Math.max(0, Math.min(max, agendaFlick.contentY + root.autoScroll * 12))
			root.updateHover()
		}
	}

	// ── Window ────────────────────────────────────────────────────────────
	FloatingWindow {
		id: window
		title: "SingularityApp"
		implicitWidth: 980
		implicitHeight: 700
		minimumSize: Qt.size(720, 520)
		color: root.themeBg
		visible: root.opened

		// Keep `opened` honest when the window manager closes the window, so
		// the next summon or toggle works. Also persists a token typed into the
		// inline setup box if the window closes without pressing Save.
		onVisibleChanged: {
			if (visible) {
				Qt.callLater(function() { content.forceActiveFocus() })
				return
			}
			if (root.service && root.tokenInput.trim() !== "") {
				root.service.saveApiToken(root.tokenInput.trim())
				root.tokenInput = ""
			}
			if (root.opened) root.close()
		}

		Item {
			id: content
			anchors.fill: parent
			focus: true

			Keys.onEscapePressed: {
				if (root.dragging) root.dragCancel()
				else if (root.showSettings) root.showSettings = false
				else if (root.addingTask) root.cancelAdd()
				else root.close()
			}

			ColumnLayout {
				anchors.fill: parent
				anchors.margins: Style.space(16)
				spacing: Style.space(8)

				// ── Header ──────────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: Style.space(8)

					Rectangle {
						Layout.preferredWidth: 32
						Layout.preferredHeight: 32
						radius: 6
						color: root.themeAccent
						Text {
							anchors.centerIn: parent
							text: ""
							color: root.themeBg
							font.family: "JetBrainsMono Nerd Font"
							font.pixelSize: 16
						}
					}

					ColumnLayout {
						Layout.fillWidth: true
						spacing: 1
						Text {
							text: "SingularityApp"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.subtitle
							font.bold: true
						}
						Text {
							text: {
								if (!root.service) return "Loading…"
								var n = root.service.todayCount
								if (root.service.loading && root.service.tasks.length === 0) return "Loading…"
								return root.todayDisplay + " · " + (n === 0 ? "nothing due" : n + " to do")
							}
							color: root.themeMuted
							font.family: root.fontFamily
							font.pixelSize: Style.font.caption
						}
					}

					Button {
						text: "List"
						foreground: root.themeFg
						selected: root.tab === "list"
						onClicked: root.tab = "list"
					}

					Button {
						text: "Agenda"
						foreground: root.themeFg
						selected: root.tab === "agenda"
						onClicked: {
							root.tab = "agenda"
							Qt.callLater(root.scrollAgendaToDefault)
						}
					}

					Button {
						iconText: ""
						foreground: root.themeMuted
						tooltipText: "Settings"
						onClicked: {
							root.showSettings = true
							root.syncSettingsToControls()
						}
					}

					Button {
						iconText: ""
						foreground: root.themeFg
						tooltipText: "Close (Esc)"
						onClicked: root.close()
					}
				}

				Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.lineColor }

				// ── Messages ────────────────────────────────────────────────
				Text {
					Layout.fillWidth: true
					visible: root.panelError !== ""
					text: root.panelError
					color: root.themeUrgent
					font.family: root.fontFamily
					font.pixelSize: Style.font.caption
					wrapMode: Text.WordWrap
				}

				Text {
					Layout.fillWidth: true
					visible: root.panelSuccess !== ""
					text: root.panelSuccess
					color: root.themeAccent
					font.family: root.fontFamily
					font.pixelSize: Style.font.caption
				}

				// ── API token setup ─────────────────────────────────────────
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: tokenSetupColumn.implicitHeight + Style.space(20)
					visible: root.service && (!root.service.settings || root.service.settings.apiToken === "" || root.service.error !== "")
					radius: Style.cornerRadius
					color: root.surfaceBg
					border.color: root.themeUrgent
					border.width: 1

					ColumnLayout {
						id: tokenSetupColumn
						anchors.left: parent.left
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						anchors.margins: Style.space(10)
						spacing: Style.space(6)

						Text {
							Layout.fillWidth: true
							text: root.service && root.service.error !== "" ? root.service.error : "Add your SingularityApp API token to get started."
							color: root.themeUrgent
							font.family: root.fontFamily
							font.pixelSize: Style.font.caption
							wrapMode: Text.WordWrap
						}

						RowLayout {
							Layout.fillWidth: true
							spacing: Style.space(6)

							TextField {
								Layout.fillWidth: true
								placeholderText: "API token"
								password: true
								text: root.tokenInput
								foreground: root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								onTextChanged: root.tokenInput = text
								Keys.onPressed: function(event) {
									if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.service && root.tokenInput.trim() !== "") {
										root.service.saveApiToken(root.tokenInput.trim())
										root.tokenInput = ""
									}
								}
							}

							Button {
								text: "Save"
								foreground: root.themeAccent
								selected: true
								bordered: true
								onClicked: {
									if (root.service && root.tokenInput.trim() !== "") {
										root.service.saveApiToken(root.tokenInput.trim())
										root.tokenInput = ""
									}
								}
							}
						}
					}
				}

				// ── Body: List / Agenda ─────────────────────────────────────
				Item {
					Layout.fillWidth: true
					Layout.fillHeight: true

					// ════════════ LIST TAB ════════════
					ColumnLayout {
						anchors.fill: parent
						visible: root.tab === "list"
						spacing: Style.space(8)

						// Add task
						Rectangle {
							Layout.fillWidth: true
							Layout.preferredHeight: addColumn.implicitHeight + Style.space(20)
							radius: Style.cornerRadius
							color: root.surfaceBg
							border.color: root.lineColor
							border.width: 1

							ColumnLayout {
								id: addColumn
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								anchors.margins: Style.space(10)
								spacing: Style.space(6)

								RowLayout {
									Layout.fillWidth: true
									visible: !root.addingTask
									spacing: Style.space(8)
									Button {
										text: "+"
										foreground: root.themeAccent
										fontSize: Style.font.title
										onClicked: {
											root.addingTask = true
											Qt.callLater(function() { titleField.forceActiveFocus() })
										}
									}
									Text {
										Layout.fillWidth: true
										text: "Add a task"
										color: root.themeMuted
										font.family: root.fontFamily
										font.pixelSize: Style.font.body
									}
								}

								TextField {
									id: titleField
									Layout.fillWidth: true
									visible: root.addingTask
									placeholderText: "What needs to be done?"
									text: root.newTitle
									foreground: root.themeFg
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									onTextChanged: root.newTitle = text
									Keys.onPressed: function(event) {
										if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.addTask()
										else if (event.key === Qt.Key_Escape) { root.cancelAdd(); event.accepted = true }
									}
								}

								RowLayout {
									Layout.fillWidth: true
									visible: root.addingTask
									spacing: Style.space(6)

									Dropdown {
										Layout.preferredWidth: 170
										showLabel: false
										options: [{ value: "", label: "No project" }].concat(
											root.service ? root.service.projects.map(function(p) { return { value: p.id, label: p.title } }) : [])
										value: root.newProjectId
										foreground: root.themeFg
										accent: root.themeAccent
										onChanged: function(v) { root.newProjectId = v }
									}

									MultiSelect {
										Layout.preferredWidth: 170
										showLabel: false
										noSelectionText: "Tags…"
										placeholderText: "Search tags..."
										options: root.service ? root.service.tags.map(function(t) { return { value: t.id, label: t.title } }) : []
										values: root.newTags
										foreground: root.themeFg
										accent: root.themeAccent
										onChanged: function(vals) { root.newTags = vals }
									}

									Dropdown {
										Layout.preferredWidth: 110
										showLabel: false
										enabled: root.newDay !== "none"
										options: root.timeOptions
										value: root.newTime
										foreground: root.themeFg
										accent: root.themeAccent
										onChanged: function(v) { root.newTime = v }
									}

									Item { Layout.fillWidth: true }
								}

								RowLayout {
									Layout.fillWidth: true
									visible: root.addingTask
									spacing: Style.space(4)

									Repeater {
										model: [{ v: "today", l: "Today" }, { v: "tomorrow", l: "Tomorrow" }, { v: "none", l: "No date" }]
										Button {
											text: modelData.l
											foreground: root.themeFg
											fontSize: Style.font.caption
											selected: root.newDay === modelData.v
											onClicked: root.newDay = modelData.v
										}
									}

									Item { Layout.fillWidth: true }

									Text {
										text: "Priority"
										color: root.themeMuted
										font.family: root.fontFamily
										font.pixelSize: Style.font.caption
									}

									Repeater {
										model: [{ v: 0, l: "High" }, { v: 1, l: "Normal" }, { v: 2, l: "Low" }]
										Button {
											text: modelData.l
											foreground: root.priorityColor(modelData.v)
											fontSize: Style.font.caption
											selected: root.newPriority === modelData.v
											onClicked: root.newPriority = modelData.v
										}
									}
								}

								TextField {
									Layout.fillWidth: true
									visible: root.addingTask
									placeholderText: "Note (optional)"
									text: root.newNote
									foreground: root.themeFg
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									onTextChanged: root.newNote = text
								}

								RowLayout {
									Layout.fillWidth: true
									visible: root.addingTask
									spacing: Style.space(6)

									Button {
										text: "Cancel"
										foreground: root.themeFg
										onClicked: root.cancelAdd()
									}

									Button {
										Layout.fillWidth: true
										text: "Add task"
										foreground: root.themeAccent
										selected: true
										bordered: true
										onClicked: root.addTask()
									}
								}
							}
						}

						// Task list
						ScrollView {
							id: listScroll
							Layout.fillWidth: true
							Layout.fillHeight: true
							clip: true
							contentWidth: availableWidth

							Column {
								id: taskList
								width: listScroll.availableWidth
								spacing: Style.space(2)

								Text {
									visible: root.service && root.service.overdueTasks.length > 0
									text: "Overdue"
									color: root.themeUrgent
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									font.bold: true
								}
								Repeater {
									model: root.service ? root.service.overdueTasks : []
									delegate: taskRowComponent
								}

								Text {
									visible: root.service && root.service.todayTasks.length > 0
									topPadding: Style.space(6)
									text: "Today"
									color: root.themeFg
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									font.bold: true
								}
								Repeater {
									model: root.service ? root.service.todayTasks : []
									delegate: taskRowComponent
								}

								Text {
									visible: root.service && root.service.undatedTasks.length > 0
									topPadding: Style.space(6)
									text: "No date"
									color: root.themeMuted
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									font.bold: true
								}
								Repeater {
									model: root.service ? root.service.undatedTasks : []
									delegate: taskRowComponent
								}

								Text {
									width: parent.width
									topPadding: Style.space(24)
									visible: root.service && !root.service.loading
										&& root.service.overdueTasks.length + root.service.todayTasks.length + root.service.undatedTasks.length === 0
									horizontalAlignment: Text.AlignHCenter
									text: "Nothing due — add a task above"
									color: root.themeMuted
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
								}
							}
						}
					}

					// ════════════ AGENDA TAB ════════════
					RowLayout {
						anchors.fill: parent
						visible: root.tab === "agenda"
						spacing: Style.space(12)

						// To schedule (drag sources)
						ColumnLayout {
							Layout.preferredWidth: 270
							Layout.fillHeight: true
							spacing: Style.space(6)

							Text {
								text: "To schedule"
								color: root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								font.bold: true
							}
							Text {
								Layout.fillWidth: true
								text: "Drag a task onto an hour to set its due date and time."
								color: root.themeMuted
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
								wrapMode: Text.WordWrap
							}

							ScrollView {
								id: queueScroll
								Layout.fillWidth: true
								Layout.fillHeight: true
								clip: true
								contentWidth: availableWidth

								Column {
									width: queueScroll.availableWidth
									spacing: Style.space(4)

									Repeater {
										model: root.scheduleQueue
										delegate: queueChipComponent
									}

									Text {
										width: parent.width
										topPadding: Style.space(16)
										visible: root.scheduleQueue.length === 0
										horizontalAlignment: Text.AlignHCenter
										text: "Everything is scheduled"
										color: root.themeMuted
										font.family: root.fontFamily
										font.pixelSize: Style.font.caption
									}
								}
							}
						}

						Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.lineColor }

						// Day timeline
						ColumnLayout {
							Layout.fillWidth: true
							Layout.fillHeight: true
							spacing: Style.space(6)

							RowLayout {
								Layout.fillWidth: true
								spacing: Style.space(6)

								Button {
									text: "‹"
									foreground: root.themeFg
									tooltipText: "Previous day"
									onClicked: root.shiftAgendaDay(-1)
								}
								Button {
									text: "Today"
									foreground: root.themeFg
									selected: root.service && root.currentAgendaDay === root.service.todayIso
									onClicked: root.goToToday()
								}
								Button {
									text: "›"
									foreground: root.themeFg
									tooltipText: "Next day"
									onClicked: root.shiftAgendaDay(1)
								}
								Text {
									Layout.fillWidth: true
									leftPadding: Style.space(6)
									text: root.service && root.currentAgendaDay !== ""
										? Qt.formatDate(root.service.localDate(root.currentAgendaDay), "dddd, d MMMM yyyy") : ""
									color: root.themeFg
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									font.bold: true
								}
							}

							Flickable {
								id: agendaFlick
								objectName: "agendaFlick"
								Layout.fillWidth: true
								Layout.fillHeight: true
								clip: true
								contentWidth: width
								contentHeight: 24 * root.hourHeight
								boundsBehavior: Flickable.StopAtBounds
								ScrollBar.vertical: ScrollBar {}

								Item {
									id: timeline
									width: agendaFlick.width
									height: 24 * root.hourHeight

									// Hour rows
									Repeater {
										model: 24
										Item {
											y: index * root.hourHeight
											width: timeline.width
											height: root.hourHeight
											Text {
												x: 0
												y: -height / 2 + 1
												width: root.gutterWidth - 8
												horizontalAlignment: Text.AlignRight
												visible: index > 0
												text: (index < 10 ? "0" : "") + index + ":00"
												color: root.themeMuted
												font.family: root.fontFamily
												font.pixelSize: Style.font.caption
											}
											Rectangle {
												x: root.gutterWidth
												width: parent.width - root.gutterWidth
												height: 1
												color: root.lineColor
											}
										}
									}

									// Drop target highlight
									Rectangle {
										visible: root.dragging && root.hoverHour >= 0
										x: root.gutterWidth
										y: root.hoverHour * root.hourHeight
										width: timeline.width - root.gutterWidth
										height: root.hourHeight
										color: Qt.rgba(root.themeAccent.r, root.themeAccent.g, root.themeAccent.b, 0.22)
										border.color: root.themeAccent
										border.width: 1
										Text {
											anchors.left: parent.left
											anchors.top: parent.top
											anchors.margins: 4
											text: (root.hoverHour < 10 ? "0" : "") + root.hoverHour + ":00 – "
												+ (root.hoverHour + 1 < 10 ? "0" : "") + ((root.hoverHour + 1) % 24) + ":00"
											color: root.themeAccent
											font.family: root.fontFamily
											font.pixelSize: Style.font.caption
											font.bold: true
										}
									}

									// Scheduled blocks
									Repeater {
										model: root.agendaBlocks
										delegate: blockComponent
									}

									// Current time marker
									Rectangle {
										visible: root.service && root.currentAgendaDay === root.service.todayIso
										x: root.gutterWidth
										y: root.service ? (root.service.now.getHours() * 60 + root.service.now.getMinutes()) / 60 * root.hourHeight : 0
										width: timeline.width - root.gutterWidth
										height: 2
										color: root.themeUrgent
									}
								}
							}
						}
					}
				}

				// ── Footer ──────────────────────────────────────────────────
				RowLayout {
					Layout.fillWidth: true
					spacing: Style.space(8)

					Text {
						Layout.fillWidth: true
						text: root.service ? (root.service.loading ? "Refreshing…" : "Auto-refreshes every " + Math.round(root.service.refreshMs / 60000) + " min") : ""
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
					}

					Button {
						text: "Refresh"
						foreground: root.themeFg
						onClicked: root.refresh()
					}
				}
			}

			// ── Settings popup ──────────────────────────────────────────────
			Rectangle {
				visible: root.showSettings
				anchors.fill: parent
				color: Qt.rgba(0, 0, 0, 0.45)
				z: 10
				MouseArea {
					anchors.fill: parent
					onClicked: root.showSettings = false
				}
			}

			Rectangle {
				visible: root.showSettings
				anchors.centerIn: parent
				width: Math.min(parent.width - Style.space(32), 560)
				height: settingsContent.implicitHeight + Style.space(32)
				color: root.themeBg
				radius: Style.cornerRadius
				border.color: root.lineColor
				border.width: 1
				z: 11

				MouseArea { anchors.fill: parent }

				ColumnLayout {
					id: settingsContent
					anchors.left: parent.left
					anchors.right: parent.right
					anchors.top: parent.top
					anchors.margins: Style.space(16)
					spacing: Style.space(12)

					RowLayout {
						Layout.fillWidth: true
						Text {
							Layout.fillWidth: true
							text: "Settings"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.subtitle
							font.bold: true
						}
						Button {
							iconText: ""
							foreground: root.themeMuted
							tooltipText: "Close (Esc)"
							onClicked: root.showSettings = false
						}
					}

					Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.lineColor }

					ColumnLayout {
						Layout.fillWidth: true
						spacing: Style.space(6)
						RowLayout {
							Layout.fillWidth: true
							spacing: Style.space(8)
							Text {
								Layout.preferredWidth: 130
								text: "API token"
								color: root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								font.bold: true
							}
							TextField {
								Layout.fillWidth: true
								placeholderText: "Enter your API token"
								password: true
								text: root.settingToken
								foreground: root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								onTextChanged: root.settingToken = text
							}
						}
						Text {
							Layout.fillWidth: true
							text: "Create one in SingularityApp under Personal account → API Access. Changes apply immediately."
							color: root.themeMuted
							font.family: root.fontFamily
							font.pixelSize: Style.font.caption
							wrapMode: Text.WordWrap
						}
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: Style.space(8)
						Text {
							Layout.preferredWidth: 130
							text: "Refresh (min)"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							font.bold: true
						}
						NumberField {
							value: root.settingRefreshMinutes
							from: 1
							to: 60
							stepSize: 1
							foreground: root.themeFg
							accent: root.themeAccent
							onModified: function(v) { root.settingRefreshMinutes = v }
						}
						Item { Layout.fillWidth: true }
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: Style.space(8)
						Text {
							Layout.preferredWidth: 130
							text: "Max tasks"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							font.bold: true
						}
						NumberField {
							value: root.settingMaxTasks
							from: 5
							to: 100
							stepSize: 5
							foreground: root.themeFg
							accent: root.themeAccent
							onModified: function(v) { root.settingMaxTasks = v }
						}
						Item { Layout.fillWidth: true }
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: Style.space(8)
						Text {
							Layout.preferredWidth: 130
							text: "Show completed"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							font.bold: true
						}
						Button {
							text: "Off"
							foreground: root.themeFg
							fontSize: Style.font.caption
							selected: root.settingShowCompleted === "off"
							onClicked: root.settingShowCompleted = "off"
						}
						Button {
							text: "On"
							foreground: root.themeFg
							fontSize: Style.font.caption
							selected: root.settingShowCompleted === "on"
							onClicked: root.settingShowCompleted = "on"
						}
						Item { Layout.fillWidth: true }
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: Style.space(6)
						Button {
							text: "Cancel"
							foreground: root.themeFg
							onClicked: root.showSettings = false
						}
						Button {
							Layout.fillWidth: true
							text: "Save changes"
							foreground: root.themeAccent
							selected: true
							bordered: true
							onClicked: root.saveAllSettings()
						}
					}
				}
			}

			// Drag layer: ghost that follows the cursor while dragging a task.
			Item {
				id: dragLayer
				anchors.fill: parent
				z: 100

				Rectangle {
					visible: root.dragging && root.dragTask !== null
					x: root.dragX - 24
					y: root.dragY - 14
					width: 220
					height: 28
					radius: Style.cornerRadius
					color: root.surfaceBg
					border.color: root.themeAccent
					border.width: 1
					opacity: 0.95
					Text {
						anchors.fill: parent
						anchors.leftMargin: 8
						anchors.rightMargin: 8
						verticalAlignment: Text.AlignVCenter
						elide: Text.ElideRight
						text: root.dragTask ? (root.dragTask.title || "Untitled task") : ""
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
					}
				}
			}
		}
	}

	// ── Delegates ─────────────────────────────────────────────────────────

	// One row in the List tab.
	Component {
		id: taskRowComponent

		Item {
			id: row
			property var task: modelData
			readonly property bool done: root.isDone(task)
			readonly property bool expanded: root.expandedTaskId === task.id
			width: parent ? parent.width : 0
			height: rowLayout.implicitHeight

			ColumnLayout {
				id: rowLayout
				width: parent.width
				spacing: Style.space(4)

				RowLayout {
					Layout.fillWidth: true
					spacing: Style.space(8)

					Rectangle {
						Layout.preferredWidth: 18
						Layout.preferredHeight: 18
						Layout.alignment: Qt.AlignTop
						Layout.topMargin: 3
						radius: 4
						color: row.done ? root.themeAccent : "transparent"
						border.color: row.done ? root.themeAccent : root.themeMuted
						border.width: 1
						Text {
							anchors.centerIn: parent
							visible: row.done
							text: "✓"
							color: root.themeBg
							font.pixelSize: 11
							font.bold: true
						}
						MouseArea {
							anchors.fill: parent
							cursorShape: Qt.PointingHandCursor
							onClicked: row.done ? root.uncompleteTask(row.task.id) : root.completeTask(row.task.id)
						}
					}

					ColumnLayout {
						Layout.fillWidth: true
						spacing: 1

						Text {
							Layout.fillWidth: true
							text: row.task.title || "Untitled task"
							color: row.done ? root.themeMuted : root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							font.bold: !row.done
							font.strikeout: row.done
							elide: Text.ElideRight
						}

						RowLayout {
							Layout.fillWidth: true
							spacing: Style.space(8)

							Text {
								text: root.dueLabel(row.task)
								color: root.dueColor(row.task)
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
								font.bold: root.isOverdue(row.task)
							}
							Text {
								visible: root.getTaskProject(row.task) !== null
								text: root.getTaskProject(row.task) ? "· " + root.getTaskProject(row.task).title : ""
								color: root.projectColor(row.task)
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
							}
							Repeater {
								model: root.getTaskTags(row.task)
								Text {
									text: "#" + modelData.title
									color: root.safeColor(modelData.color, root.themeMuted)
									font.family: root.fontFamily
									font.pixelSize: Style.font.caption
								}
							}
							Item { Layout.fillWidth: true }
						}
					}

					Button {
						Layout.alignment: Qt.AlignTop
						visible: !row.done
						iconText: row.expanded ? "" : ""
						foreground: root.themeMuted
						onClicked: root.expandTask(row.task.id)
					}
				}

				// Expanded actions
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: expandedColumn.implicitHeight + Style.space(16)
					visible: row.expanded
					radius: Style.cornerRadius
					color: root.surfaceBg
					border.color: root.lineColor
					border.width: 1

					Column {
						id: expandedColumn
						x: Style.space(8)
						y: Style.space(8)
						width: parent.width - Style.space(16)
						spacing: Style.space(6)

						Row {
							spacing: Style.space(6)
							Button {
								text: row.done ? "Reopen" : "Done"
								foreground: row.done ? root.themeMuted : root.themeAccent
								fontSize: Style.font.caption
								onClicked: row.done ? root.uncompleteTask(row.task.id) : root.completeTask(row.task.id)
							}
							Button {
								text: "Tomorrow"
								foreground: root.themeFg
								fontSize: Style.font.caption
								onClicked: root.postponeTask(row.task.id)
							}
							Button {
								text: root.service && root.service.hasTime(row.task) ? "Change time…" : "Schedule…"
								foreground: root.themeFg
								fontSize: Style.font.caption
								onClicked: root.timePickerTaskId = root.timePickerTaskId === row.task.id ? "" : row.task.id
							}
							Button {
								text: "Cancel task"
								foreground: root.themeUrgent
								fontSize: Style.font.caption
								onClicked: root.cancelTask(row.task.id)
							}
							Button {
								text: "Delete"
								foreground: root.themeUrgent
								fontSize: Style.font.caption
								onClicked: root.deleteTask(row.task.id)
							}
						}

						Flow {
							width: parent.width
							visible: root.timePickerTaskId === row.task.id
							spacing: Style.space(4)

							Repeater {
								model: root.timePresets
								Button {
									text: modelData.label
									foreground: root.themeFg
									fontSize: Style.font.caption
									selected: root.service && root.service.timeText(row.task) === modelData.value && root.service.dayKey(row.task) === root.service.todayIso
									onClicked: root.scheduleTask(row.task.id, modelData.value)
								}
							}
							Button {
								text: "No time"
								foreground: root.themeMuted
								fontSize: Style.font.caption
								onClicked: root.scheduleTask(row.task.id, "")
							}
						}
					}
				}

				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: 1
					color: root.lineColor
				}
			}
		}
	}

	// A draggable card in the Agenda's "To schedule" list.
	Component {
		id: queueChipComponent

		Rectangle {
			id: chip
			objectName: "queueChip"
			property var task: modelData
			width: parent ? parent.width : 0
			height: chipColumn.implicitHeight + Style.space(12)
			radius: Style.cornerRadius
			color: chipMouse.containsMouse ? Qt.rgba(root.themeFg.r, root.themeFg.g, root.themeFg.b, 0.08) : root.surfaceBg
			border.color: root.lineColor
			border.width: 1
			opacity: root.dragging && root.dragTask && root.dragTask.id === task.id ? 0.35 : 1

			Rectangle {
				x: 0
				width: 3
				height: parent.height
				color: root.projectColor(chip.task)
			}

			ColumnLayout {
				id: chipColumn
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				anchors.leftMargin: Style.space(10)
				anchors.rightMargin: Style.space(8)
				spacing: 1

				Text {
					Layout.fillWidth: true
					text: chip.task.title || "Untitled task"
					color: root.themeFg
					font.family: root.fontFamily
					font.pixelSize: Style.font.body
					elide: Text.ElideRight
				}
				Text {
					Layout.fillWidth: true
					text: root.dueLabel(chip.task)
					color: root.dueColor(chip.task)
					font.family: root.fontFamily
					font.pixelSize: Style.font.caption
					elide: Text.ElideRight
				}
			}

			MouseArea {
				id: chipMouse
				anchors.fill: parent
				hoverEnabled: true
				preventStealing: true
				cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
				property real pressX: 0
				property real pressY: 0
				onPressed: function(m) { pressX = m.x; pressY = m.y }
				onPositionChanged: function(m) {
					if (!pressed) return
					if (!root.dragging && Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 6) return
					root.dragMove(chip.task, chipMouse.mapToItem(dragLayer, m.x, m.y))
				}
				onReleased: root.dragDrop()
				onCanceled: root.dragCancel()
			}
		}
	}

	// A scheduled block on the Agenda timeline (also draggable to reschedule).
	Component {
		id: blockComponent

		Rectangle {
			id: block
			objectName: "agendaBlock"
			property var entry: modelData
			property var task: entry.task
			readonly property bool done: root.isDone(task)
			readonly property real laneWidth: (timeline.width - root.gutterWidth - 8) / entry.lanes
			x: root.gutterWidth + 2 + entry.lane * laneWidth
			y: entry.start / 60 * root.hourHeight + 1
			width: laneWidth - 3
			height: Math.max(22, (entry.end - entry.start) / 60 * root.hourHeight - 2)
			radius: Style.cornerRadius
			color: Qt.rgba(root.projectColor(task).r, root.projectColor(task).g, root.projectColor(task).b, 0.28)
			border.color: root.projectColor(task)
			border.width: 1
			opacity: (root.dragging && root.dragTask && root.dragTask.id === task.id) ? 0.35 : (done ? 0.55 : 1)
			clip: true

			MouseArea {
				id: blockMouse
				anchors.fill: parent
				preventStealing: true
				cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
				property real pressX: 0
				property real pressY: 0
				onPressed: function(m) { pressX = m.x; pressY = m.y }
				onPositionChanged: function(m) {
					if (!pressed) return
					if (!root.dragging && Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 6) return
					root.dragMove(block.task, blockMouse.mapToItem(dragLayer, m.x, m.y))
				}
				onReleased: root.dragDrop()
				onCanceled: root.dragCancel()
			}

			RowLayout {
				anchors.fill: parent
				anchors.margins: 4
				spacing: 4

				ColumnLayout {
					Layout.fillWidth: true
					Layout.alignment: Qt.AlignTop
					spacing: 0
					Text {
						Layout.fillWidth: true
						text: block.task.title || "Untitled task"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.strikeout: block.done
						elide: Text.ElideRight
					}
					Text {
						Layout.fillWidth: true
						visible: block.height >= 40
						text: root.service ? root.service.timeText(block.task) + (block.task.timeLength > 0 ? "–" + root.endTimeText(block.task) : "") : ""
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
						elide: Text.ElideRight
					}
				}

				Button {
					Layout.alignment: Qt.AlignTop
					iconText: block.done ? "" : ""
					foreground: block.done ? root.themeMuted : root.themeAccent
					tooltipText: block.done ? "Reopen" : "Done"
					onClicked: block.done ? root.uncompleteTask(block.task.id) : root.completeTask(block.task.id)
				}
			}
		}
	}
}
