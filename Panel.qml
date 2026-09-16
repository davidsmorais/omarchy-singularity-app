import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SingularityApp panel: daily task planner for Omarchy.
// Shows today's tasks, quick actions (complete / postpone / cancel / schedule),
// and a rich create form with project, tags, date and time.
//
// Summon with:  omarchy-shell shell summon david.singularity '{}'

Item {
	id: root

	component TaskRowDelegate: Rectangle {
		id: taskRow
		required property var modelData
		width: parent.width
		color: "transparent"
		property var task: modelData
		property bool taskDone: root.isTaskDone(task)
		property bool expanded: root.expandedTaskId === task.id
		height: taskContent.implicitHeight + (expanded ? expandedContent.implicitHeight + Style.space(4) : 0)

		// Main task row
		Column {
			id: taskContent
			width: parent.width - Style.space(12)
			anchors.left: parent.left
			anchors.leftMargin: Style.space(12)
			spacing: Style.space(2)

			Row {
				width: parent.width
				spacing: Style.space(6)

				// Complete checkbox
				Rectangle {
					id: taskCheck
					width: 18
					height: 18
					radius: 4
					color: taskDone ? root.themeAccent : "transparent"
					border.color: taskDone ? root.themeAccent : root.themeMuted
					border.width: 1.5

					Text {
						anchors.centerIn: parent
						visible: taskDone
						text: "\u2713"
						color: root.themeBg
						font.pixelSize: 11
						font.bold: true
					}

					MouseArea {
						anchors.fill: parent
						cursorShape: Qt.PointingHandCursor
						onClicked: {
							if (taskDone) root.uncompleteTask(task.id)
							else root.completeTask(task.id)
						}
					}
				}

				Item {
					width: parent.width - 24
					height: taskInfoColumn.implicitHeight
					Column {
						id: taskInfoColumn
						width: parent.width
						spacing: 1

						// Title row
						Row {
							width: parent.width
							spacing: Style.space(6)

							Text {
								text: task.title || "Untitled task"
								color: taskDone ? root.themeMuted : root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								font.bold: !taskDone
								font.strikeout: taskDone
								elide: Text.ElideRight
								width: parent.width - timeLabel.implicitWidth - dateLabel.implicitWidth - projectLabel.implicitWidth - Style.space(12)
							}

							// Time
							Text {
								id: timeLabel
								text: root.taskHasTime(task) ? root.formatTime(task) : ""
								color: root.themeMuted
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
							}

							// Due date
							Text {
								id: dateLabel
								text: root.dateLabelText(task)
								color: root.isOverdue(task) ? root.themeUrgent : root.themeMuted
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
								font.bold: root.isOverdue(task)
							}

							// Project indicator
							Text {
								id: projectLabel
								text: root.getTaskProject(task) ? "\u00B7 " + root.getTaskProject(task).title : ""
								color: root.getTaskProject(task) ? root.getTaskProject(task).color : root.themeMuted
								font.family: root.fontFamily
								font.pixelSize: Style.font.caption
							}
						}

						// Tags
						Row {
							visible: root.getTaskTags(task).length > 0
							width: parent.width
							spacing: Style.space(3)
							Text {
								text: "\u2002"
								color: "transparent"
								font.pixelSize: 1
							}
							Repeater {
								model: root.getTaskTags(task)
								Text {
									text: "#" + modelData.title
									color: modelData.color !== "" ? modelData.color : root.themeMuted
									font.family: root.fontFamily
									font.pixelSize: Style.font.caption
								}
							}
						}
					}
				}
			}

			// Expand button
			Text {
				text: "\u25BC"
				color: root.themeMuted
				font.family: root.fontFamily
				font.pixelSize: Style.font.caption
				visible: !taskDone
				width: 30
				height: 20
				anchors.right: parent.right
				anchors.rightMargin: Style.space(12)
				MouseArea {
					anchors.fill: parent
					cursorShape: Qt.PointingHandCursor
					onClicked: root.expandTask(task.id)
				}
			}

			// Divider
			Rectangle {
				width: parent.width
				height: 1
				color: root.lineColor
				opacity: 0.4
			}
		}

		// Expanded actions panel
		Column {
			id: expandedContent
			visible: expanded
			width: parent.width
			anchors.left: parent.left
			anchors.leftMargin: Style.space(12)
			spacing: Style.space(4)
			opacity: expanded ? 1 : 0

			// Animate in
			Behavior on opacity { NumberAnimation { duration: 120 } }

			Rectangle {
				width: parent.width
				height: expandedActionsColumn.implicitHeight + Style.space(16)
				radius: Style.cornerRadius
				color: root.surfaceBg
				border.color: root.lineColor
				border.width: 1

				Column {
					id: expandedActionsColumn
					anchors.centerIn: parent
					width: parent.width - Style.space(16)
					spacing: Style.space(6)

					// Quick actions
					Row {
						width: parent.width
						spacing: Style.space(6)

						Button {
							width: 100
							text: taskDone ? "Reopen" : "Done"
							foreground: taskDone ? root.themeMuted : root.themeAccent
							fontSize: Style.font.caption
							onClicked: taskDone ? root.uncompleteTask(task.id) : root.completeTask(task.id)
						}

						Button {
							width: 100
							text: "Tomorrow"
							foreground: root.themeFg
							fontSize: Style.font.caption
							onClicked: root.postponeTask(task.id)
						}

						Button {
							width: 100
							text: "Cancel"
							foreground: root.themeUrgent
							fontSize: Style.font.caption
							onClicked: root.cancelTask(task.id)
						}

						Button {
							width: parent.width - 300
							text: root.taskHasTime(task) ? "Change time\u2026" : "Schedule\u2026"
							foreground: root.themeFg
							fontSize: Style.font.caption
							onClicked: {
								// Show time picker for this task
								root.showTimePicker = true
								root.expandedTaskId = task.id
							}
						}
					}

					// Time picker
					Row {
						visible: root.showTimePicker
						width: parent.width
						spacing: Style.space(4)

						Text {
							text: "Set time for today"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.caption
						}

						Repeater {
							model: root.timePresets

							Button {
								width: 60
								text: modelData.label
								foreground: modelData.value === "" ? root.themeMuted : root.themeFg
								fontSize: Style.font.caption
								selected: root.formatTime(task) === modelData.value || (modelData.value === "" && !root.taskHasTime(task))
								onClicked: {
									root.scheduleTask(task.id, modelData.value)
									root.showTimePicker = false
								}
							}
						}

						Button {
							width: 60
							text: "\u2715"
							foreground: root.themeMuted
							fontSize: Style.font.caption
							onClicked: root.showTimePicker = false
						}
					}

					// Delete button
					Button {
						width: parent.width
						text: "Delete task"
						foreground: root.themeUrgent
						fontSize: Style.font.caption
						onClicked: root.deleteTask(task.id)
					}
				}
			}
		}
	}

	property var bar: null
	property var shell: null
	property var service: null
	property var manifest: null

	readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "david.singularity"

	// ── Panel state ───────────────────────────────────────────────────────
	property bool opened: false
	property bool popoutSwitchClosing: false
	property bool addingTask: false
	property string newTitle: ""
	property string newNote: ""
	property int newPriority: 1
	property string newDate: ""
	property string newTime: ""
	property string newProjectId: ""
	property var newTags: []
	property string panelError: ""
	property string panelSuccess: ""
	property string tokenInput: ""

	// Task row: expanding action panel
	property var expandedTaskId: ""

	// Time presets for scheduling
	readonly property var timePresets: [
		{ label: "9:00",  value: "09:00" },
		{ label: "10:00", value: "10:00" },
		{ label: "11:00", value: "11:00" },
		{ label: "12:00", value: "12:00" },
		{ label: "13:00", value: "13:00" },
		{ label: "14:00", value: "14:00" },
		{ label: "15:00", value: "15:00" },
		{ label: "16:00", value: "16:00" },
		{ label: "17:00", value: "17:00" },
		{ label: "18:00", value: "18:00" },
		{ label: "19:00", value: "19:00" },
		{ label: "20:00", value: "20:00" },
		{ label: "21:00", value: "21:00" },
		{ label: "No time", value: "" }
	]

	// ── Settings popup ─────────────────────────────────────────────────────
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
		if (root.settingToken !== service.settings.apiToken) {
			service.saveSetting("apiToken", root.settingToken)
		}
		if (root.settingRefreshMinutes !== parseInt(String(service.settings.refreshMinutes || 5), 10)) {
			service.saveSetting("refreshMinutes", String(root.settingRefreshMinutes))
		}
		if (root.settingMaxTasks !== parseInt(String(service.settings.maxTasks || 50), 10)) {
			service.saveSetting("maxTasks", String(root.settingMaxTasks))
		}
		if (root.settingShowCompleted !== (service.settings.showCompleted || "off")) {
			service.saveSetting("showCompleted", root.settingShowCompleted)
		}
		root.showSettings = false
	}

	// ── Theme ─────────────────────────────────────────────────────────────
	readonly property color themeBg: Color.background
	readonly property color themeFg: Color.foreground
	readonly property color themeAccent: Color.accent
	readonly property color themeMuted: Color.muted
	readonly property color themeUrgent: Color.urgent
	readonly property color surfaceBg: Qt.rgba(themeBg.r, themeBg.g, themeBg.b, 0.96)
	readonly property color lineColor: Qt.rgba(
		themeFg.r * 0.08, themeFg.g * 0.08, themeFg.b * 0.08, 1)
	readonly property string fontFamily: {
		var families = Qt.fontFamilies()
		if (families.indexOf("JetBrains Mono") >= 0) return "JetBrains Mono"
		if (families.indexOf("JetBrainsMono Nerd Font") >= 0) return "JetBrainsMono Nerd Font"
		return families[0] || "sans-serif"
	}

	readonly property string todayDisplay: Qt.formatDate(new Date(), "dddd, d MMMM")

	readonly property int maxTasks: parseInt(String(settings.maxTasks || 50), 10) || 50

	// ── Task helpers ──────────────────────────────────────────────────────
	function getTaskProject(task) {
		if (!task || !task.projectId) return null
		for (var i = 0; i < service.projects.length; i++) {
			if (service.projects[i].id === task.projectId) return service.projects[i]
		}
		return null
	}

	function getTaskTags(task) {
		if (!task || !task.tags) return []
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

	function formatTime(task) {
		if (!task.start || task.start === "") return ""
		var time = task.start.slice(11, 16)
		if (time === "00:00") return ""
		return time
	}

	function priorityLabel(p) {
		if (p === 0) return "High"
		if (p === 2) return "Low"
		return "Normal"
	}

	function priorityColor(p) {
		if (p === 0) return themeUrgent
		if (p === 2) return themeAccent
		return themeMuted
	}

	function taskHasTime(task) {
		if (!task.start || task.start === "") return false
		var time = task.start.slice(11, 16)
		return time !== "00:00"
	}

	function isTaskDone(task) {
		return task.complete === 1 || task.journalDate || task.removed === true
	}

	function isOverdue(task) {
		if (!task || !task.start || task.start === "") return false
		if (!service) return false
		return task.start.slice(0, 10) < service.todayIso
	}

	function formatDateShort(task) {
		if (!task || !task.start || task.start === "") return ""
		var dateStr = task.start.slice(0, 10)
		var d = new Date(dateStr + "T00:00:00Z")
		if (isNaN(d.getTime())) return dateStr
		return Qt.formatDate(d, "d MMM")
	}

	function dateLabelText(task) {
		if (!task || !task.start || task.start === "") return ""
		if (root.isOverdue(task)) return "Overdue \u00B7 " + root.formatDateShort(task)
		if (task.start.slice(0, 10) === service.todayIso) return "Today"
		return root.formatDateShort(task)
	}

	// ── Panel lifecycle ───────────────────────────────────────────────────
	function openPanel() {
		opened = true
	}

	function close() {
		opened = false
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
		opened = true
		if (service) service.openPanel()
	}

	function refresh() {
		if (service) service.refresh()
		panelError = ""
		panelSuccess = ""
	}

	function cancelAdd() {
		addingTask = false
		panelError = ""
	}

	// ── Add task ──────────────────────────────────────────────────────────
	function addTask() {
		var title = newTitle.trim()
		if (!title) { panelError = "Task title is required"; return }
		panelError = ""
		panelSuccess = ""
		var priority = newPriority
		var startDate = newDate.trim() || (service ? service.todayIso : "")
		var time = newTime.trim()
		if (time !== "") {
			startDate = startDate + "T" + time + ":00.000Z"
		}
		var projectId = newProjectId || ""
		var tags = newTags ? newTags.slice() : []
		if (service) service.addTask(title, newNote, priority, startDate, projectId, tags)
		newTitle = ""
		newNote = ""
		newPriority = 1
		newDate = ""
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
	}

	function deleteTask(taskId) {
		if (service) service.deleteTask(taskId)
		panelError = ""
		expandedTaskId = ""
	}

	function expandTask(taskId) {
		if (expandedTaskId === taskId) expandedTaskId = ""
		else expandedTaskId = taskId
	}

	// ── Window ────────────────────────────────────────────────────────────
	property int windowWidth: 720
	property int windowHeight: Math.max(520, 480)

	FloatingWindow {
		id: window
		title: "SingularityApp"
		implicitWidth: windowWidth
		implicitHeight: windowHeight
		minimumSize: Qt.size(500, 400)
		color: root.themeBg
		visible: root.opened

		onClosing: {
			// Persist any pending token entered in the inline setup box so it
			// survives a shell restart even if the user closes the panel without
			// explicitly pressing Save inside the token field.
			if (service && root.tokenInput.trim() !== "") {
				service.saveApiToken(root.tokenInput.trim())
				root.tokenInput = ""
			}
		}

		onVisibleChanged: if (visible) Qt.callLater(function() { contentColumn.forceActiveFocus() })

		// ── Panel content ─────────────────────────────────────────────────────
		Column {
			id: contentColumn
			focus: true
			anchors.fill: parent
			anchors.margins: Style.space(16)
			spacing: Style.space(8)

			// ── Header ──────────────────────────────────────────────────────────
			Row {
				width: parent.width
				spacing: Style.space(8)

				Item {
					width: 32
					height: 32
					Rectangle {
						anchors.fill: parent
						color: root.themeAccent
						radius: 6
						Canvas {
							anchors.fill: parent
							property real cx: width / 2
							property real cy: height / 2
							property real r: Math.min(width, height) / 2 - 2
							onPaint: function() {
								var ctx = getContext("2d")
								ctx.clearRect(0, 0, width, height)
								ctx.beginPath()
								ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 1.5)
								ctx.lineTo(cx + r * Math.cos(-Math.PI / 2 + Math.PI * 1.5), cy + r * Math.sin(-Math.PI / 2 + Math.PI * 1.5))
								ctx.closePath()
								ctx.fillStyle = themeBg
								ctx.fill()
								ctx.strokeStyle = themeBg
								ctx.lineWidth = 2
								ctx.stroke()
							}
						}
					}
				}

				Column {
					width: parent.width - 32 - closeButton.width - settingsButton.width - Style.space(8)
					spacing: 1

					Text {
						text: "SingularityApp"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.subtitle
						font.bold: true
					}
					Text {
						text: service && service.todayCount > 0
							? root.todayDisplay + " \u00B7 " + service.todayCount + " task" + (service.todayCount === 1 ? "" : "s")
							: (service && service.todayCount === 0 && !service.loading ? "No tasks for today" : "Loading\u2026")
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
					}
				}

				Button {
					id: closeButton
					width: 32
					height: 32
					iconText: "\uF00C"
					foreground: root.themeFg
					tooltipText: "Close (Esc)"
					onClicked: root.close()
				}

				// Settings gear button
				Button {
					width: 32
					height: 32
					iconText: "\uF013"
					foreground: root.themeMuted
					tooltipText: "Settings"
					onClicked: {
						root.showSettings = true
						root.syncSettingsToControls()
					}
				}
			}

			Rectangle {
				width: 1
				height: 1
				color: root.lineColor
			}

			// ── Panel error / success messages ──────────────────────────────────
			Text {
				text: panelError
				color: root.themeUrgent
				font.family: root.fontFamily
				font.pixelSize: Style.font.caption
				visible: panelError !== ""
				anchors.margins: 0
			}

			Text {
				text: panelSuccess
				color: root.themeAccent
				font.family: root.fontFamily
				font.pixelSize: Style.font.caption
				visible: panelSuccess !== ""
				anchors.margins: 0
			}

			// ── API token setup ─────────────────────────────────────────────────
			Rectangle {
				width: parent.width
				height: tokenSetupColumn.implicitHeight + Style.space(20)
				visible: service && (!service.settings || service.settings.apiToken === "" || service.error !== "")
				radius: Style.cornerRadius
				color: root.surfaceBg
				border.color: root.themeUrgent
				border.width: 1

				Column {
					id: tokenSetupColumn
					anchors.centerIn: parent
					width: parent.width - Style.space(20)
					spacing: Style.space(6)

					Text {
						width: parent.width
						text: service && service.error !== "" ? service.error : "Add your SingularityApp API token to get started."
						color: root.themeUrgent
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
						wrapMode: Text.WordWrap
					}

					Row {
						width: parent.width
						spacing: Style.space(6)

						TextField {
							id: tokenField
							width: parent.width - saveTokenButton.width - Style.space(6)
							placeholderText: "API token"
							password: true
							text: root.tokenInput
							foreground: root.themeFg
							placeholderTextColor: root.themeMuted
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							onTextChanged: root.tokenInput = text
							Keys.onPressed: function(event) {
								if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
									if (service && root.tokenInput.trim() !== "") {
										service.saveApiToken(root.tokenInput.trim())
										root.tokenInput = ""
									}
								}
							}
						}

						Button {
							id: saveTokenButton
							width: 70
							text: "Save"
							foreground: root.themeAccent
							selected: true
							bordered: true
							onClicked: {
								if (service && root.tokenInput.trim() !== "") {
									service.saveApiToken(root.tokenInput.trim())
									root.tokenInput = ""
								}
							}
						}
					}
				}
			}

			// ── Add task form ───────────────────────────────────────────────────
			Rectangle {
				width: parent.width
				height: addTaskColumn.implicitHeight + Style.space(20)
				radius: Style.cornerRadius
				color: root.surfaceBg
				border.color: root.lineColor
				border.width: 1

				Column {
					id: addTaskColumn
					anchors.centerIn: parent
					width: parent.width - Style.space(20)
					spacing: Style.space(6)

					Row {
						width: parent.width
						spacing: Style.space(6)

						// Toggle add form button
						Button {
							width: addingTask ? 0 : 32
							height: 32
							text: "+"
							foreground: root.themeAccent
							fontSize: Style.font.display
							enabled: !addingTask
							onClicked: addingTask = true
						}

						Item {
							width: parent.width - (addingTask ? 0 : 32) - Style.space(8)
							height: quickAddColumn.implicitHeight
							Column {
								id: quickAddColumn
								width: parent.width
								spacing: Style.space(4)

								Text {
									text: addingTask ? "Add a task for today" : "Quick add"
									color: root.themeFg
									font.family: root.fontFamily
									font.pixelSize: Style.font.body
									font.bold: true
								}

								Column {
									width: parent.width
									spacing: Style.space(6)
									visible: addingTask

									// Title input
									TextField {
										width: parent.width
										placeholderText: "What needs to be done?"
										text: root.newTitle
										foreground: root.themeFg
										placeholderTextColor: root.themeMuted
										font.family: root.fontFamily
										font.pixelSize: Style.font.body
										onTextChanged: root.newTitle = text
										Keys.onPressed: function(event) {
											if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
												root.addTask()
											} else if (event.key === Qt.Key_Escape) {
												root.cancelAdd()
											}
										}
									}

									// Project + Tags row
									Row {
										width: parent.width
										spacing: Style.space(6)

										// Project dropdown
										Dropdown {
											width: 160
											showLabel: false
											options: [{ value: "", label: "No project" }].concat(
												service ? service.projects.map(function(p) { return { value: p.id, label: p.title } }) : [])
											value: root.newProjectId
											foreground: root.themeFg
											accent: root.themeAccent
											onChanged: function(v) { root.newProjectId = v }
										}

										// Tags multi-select
										MultiSelect {
											width: 160
											showLabel: false
											noSelectionText: "Tags\u2026"
											placeholderText: "Search tags..."
											options: service ? service.tags.map(function(t) { return { value: t.id, label: t.title } }) : []
											values: root.newTags
											foreground: root.themeFg
											accent: root.themeAccent
											onChanged: function(vals) { root.newTags = vals }
										}

										Item {
											width: parent.width - 160 - 120 - Style.space(24)
											height: dateTimePriorityColumn.implicitHeight
											Column {
												id: dateTimePriorityColumn
												width: parent.width
												spacing: 2

												// Date + Time row
												Row {
													width: parent.width
													spacing: Style.space(6)

													Row {
														width: 130
														spacing: Style.space(4)

														Button {
															width: 61
															text: "Today"
															foreground: root.themeFg
															fontSize: Style.font.caption
															selected: root.newDate === "" || (service && root.newDate === service.todayIso)
															onClicked: root.newDate = service ? service.todayIso : ""
														}

														Button {
															width: 61
															text: "Tomorrow"
															foreground: root.themeFg
															fontSize: Style.font.caption
															selected: service && root.newDate === service.tomorrowIso
															onClicked: root.newDate = service ? service.tomorrowIso : ""
														}
													}

													Item {
														width: 100
														height: timeColumn.implicitHeight
														Column {
															id: timeColumn
															width: parent.width
															spacing: 1
															Text {
																text: "Time"
																color: root.themeMuted
																font.family: root.fontFamily
																font.pixelSize: Style.font.caption
															}
															Dropdown {
																width: parent.width
																showLabel: false
																options: root.timePresets
																value: root.newTime
																foreground: root.themeFg
																accent: root.themeAccent
																onChanged: function(v) { root.newTime = v }
															}
														}
													}

													Item {
														width: parent.width - 130 - 100 - Style.space(6)
														height: priorityColumn.implicitHeight
														Column {
															id: priorityColumn
															width: parent.width
															spacing: 2
															Text {
																text: "Priority"
																color: root.themeMuted
																font.family: root.fontFamily
																font.pixelSize: Style.font.caption
															}
															Row {
																spacing: Style.space(4)
																Repeater {
																	model: [{ v: 0, l: "High" }, { v: 1, l: "Normal" }, { v: 2, l: "Low" }]
																	Button {
																		width: 52
																		height: 26
																		text: modelData.l
																		foreground: root.priorityColor(modelData.v)
																		fontSize: Style.font.caption
																		selected: root.newPriority === modelData.v
																		onClicked: root.newPriority = modelData.v
																	}
																}
															}
														}
													}
												}

												// Note input
												TextField {
													width: parent.width
													placeholderText: "Note (optional)"
													text: root.newNote
													foreground: root.themeFg
													placeholderTextColor: root.themeMuted
													font.family: root.fontFamily
													font.pixelSize: Style.font.body
													onTextChanged: root.newNote = text
												}
											}
										}
									}

									// Add / Cancel buttons
									Row {
										width: parent.width
										spacing: Style.space(6)

										Button {
											width: 80
											text: "Cancel"
											foreground: root.themeFg
											enabled: addingTask
											onClicked: root.cancelAdd()
										}

										Button {
											width: parent.width - 80
											text: "Add task"
											foreground: root.themeAccent
											selected: true
											bordered: true
											enabled: addingTask
											onClicked: root.addTask()
										}
									}
								}

								// Idle state: show a hint
								Text {
									visible: !addingTask
									text: "Click + or press Enter to add a task"
									color: root.themeMuted
									font.family: root.fontFamily
									font.pixelSize: Style.font.caption
								}
							}
						}
					}
				}
			}

			Rectangle {
				width: 1
				height: 1
				color: root.lineColor
			}

			// ── Task list ────────────────────────────────────────────────────────────────────
			ScrollView {
				id: taskScrollView
				width: parent.width
				height: parent.height - 40
				clip: true
				contentWidth: availableWidth
				contentHeight: taskList.implicitHeight

				Column {
					id: taskList
					width: taskScrollView.availableWidth
					spacing: Style.space(2)

					readonly property var overdueTasks: service
						? service.sortTodayTasks(service.todayTasks.filter(function(t) { return root.isOverdue(t) })) : []
					readonly property var todaysTasks: service
						? service.sortTodayTasks(service.todayTasks.filter(function(t) { return !root.isOverdue(t) })) : []

					Text {
						visible: taskList.overdueTasks.length > 0
						text: "Overdue"
						color: root.themeUrgent
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.bold: true
					}

					Repeater {
						model: taskList.overdueTasks
						delegate: TaskRowDelegate {}
					}

					Text {
						text: "Today"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.bold: true
					}

					Repeater {
						model: taskList.todaysTasks
						delegate: TaskRowDelegate {}
					}

					// Empty state
					Item {
						width: parent.width
						height: (service && service.todayTasks.length === 0 && !service.loading) ? emptyState.implicitHeight : 0

						Column {
							id: emptyState
							width: parent.width
							anchors.centerIn: parent
							spacing: Style.space(6)
							opacity: 0.6

							Text {
								text: "\uF044"
								color: root.themeFg
								font.family: "JetBrainsMono Nerd Font"
								font.pixelSize: Style.font.display
								anchors.horizontalCenter: parent.horizontalCenter
							}

							Text {
								text: service && service.loading ? "Loading tasks\u2026" : "No tasks for today \u2014 add one above"
								color: root.themeFg
								font.family: root.fontFamily
								font.pixelSize: Style.font.body
								anchors.horizontalCenter: parent.horizontalCenter
							}
						}
					}
				}
			}

			// ── Footer ──────────────────────────────────────────────────────────
			Row {
				width: parent.width
				spacing: Style.space(8)

				Item {
					width: parent.width - refreshButton.width
					height: refreshButton.height
					Text {
						text: service ? "Auto-refreshes every " + service.refreshMs / 60000 + " min" : ""
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
						anchors.verticalCenter: parent.verticalCenter
					}
				}

				Button {
					id: refreshButton
					width: 80
					text: "Refresh"
					foreground: root.themeFg
					onClicked: root.refresh()
				}
			}
		}

		// ── Settings popup overlay ─────────────────────────────────────────────────────
		Rectangle {
			id: settingsOverlay
			visible: root.showSettings
			anchors.fill: parent
			color: Qt.rgba(0, 0, 0, 0.35)
			z: 10
			MouseArea {
				anchors.fill: parent
				onClicked: root.showSettings = false
			}
		}

		Rectangle {
			id: settingsCard
			visible: root.showSettings
			anchors.centerIn: parent
			width: parent.width - Style.space(32)
			color: root.surfaceBg
			radius: Style.cornerRadius
			border.color: root.lineColor
			border.width: 1
			z: 11

			Column {
				id: settingsContent
				anchors.fill: parent
				anchors.margins: Style.space(16)
				spacing: Style.space(12)

				// Header
				Row {
					width: parent.width
					spacing: Style.space(8)

					Text {
						text: "Settings"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.subtitle
						font.bold: true
					}

					Item {
						fillWidth: true
					}

					Button {
						width: 32
						height: 32
						iconText: "\uF00D"
						foreground: root.themeMuted
						tooltipText: "Close (Esc)"
						onClicked: root.showSettings = false
					}
				}

				Rectangle {
					width: 1
					height: 1
					color: root.lineColor
				}

				// API Token
				Column {
					width: parent.width
					spacing: Style.space(6)

					Row {
						width: parent.width
						spacing: Style.space(8)

						Text {
							width: 120
							text: "API token"
							color: root.themeFg
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							font.bold: true
							verticalAlignment: Text.AlignVCenter
						}

						TextField {
							width: parent.width - 120
							placeholderText: "Enter your API token"
							password: true
							text: root.settingToken
							foreground: root.themeFg
							placeholderTextColor: root.themeMuted
							font.family: root.fontFamily
							font.pixelSize: Style.font.body
							onTextChanged: root.settingToken = text
						}
					}

					Text {
						width: parent.width
						text: "Get your token from SingularityApp under Account \u2192 API Access. Changes apply immediately."
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.caption
						wrapMode: Text.WordWrap
					}
				}

				Rectangle {
					width: 1
					height: 1
					color: root.lineColor
				}

				// Refresh interval
				Row {
					width: parent.width
					spacing: Style.space(8)

					Text {
						width: 120
						text: "Refresh (min)"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.bold: true
						verticalAlignment: Text.AlignVCenter
					}

					Spinner {
						width: 100
						value: root.settingRefreshMinutes
						minimumValue: 1
						maximumValue: 60
						stepSize: 1
						verticalAlignment: Text.AlignVCenter
						onValueChanged: root.settingRefreshMinutes = value
					}

					Text {
						width: 60
						text: root.settingRefreshMinutes + " min"
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						verticalAlignment: Text.AlignVCenter
					}
				}

				Rectangle {
					width: 1
					height: 1
					color: root.lineColor
				}

				// Max tasks
				Row {
					width: parent.width
					spacing: Style.space(8)

					Text {
						width: 120
						text: "Max tasks"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.bold: true
						verticalAlignment: Text.AlignVCenter
					}

					Spinner {
						width: 100
						value: root.settingMaxTasks
						minimumValue: 5
						maximumValue: 100
						stepSize: 5
						verticalAlignment: Text.AlignVCenter
						onValueChanged: root.settingMaxTasks = value
					}

					Text {
						width: 60
						text: root.settingMaxTasks + " tasks"
						color: root.themeMuted
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						verticalAlignment: Text.AlignVCenter
					}
				}

				Rectangle {
					width: 1
					height: 1
					color: root.lineColor
				}

				// Show completed
				Row {
					width: parent.width
					spacing: Style.space(8)

					Text {
						width: 120
						text: "Show completed"
						color: root.themeFg
						font.family: root.fontFamily
						font.pixelSize: Style.font.body
						font.bold: true
						verticalAlignment: Text.AlignVCenter
					}

					Item {
						width: parent.width - 120
						height: 26
						Row {
							spacing: Style.space(4)
							anchors.centerIn: parent

							Button {
								width: 80
								text: "Off"
								foreground: root.settingShowCompleted === "off" ? root.themeAccent : root.themeMuted
								fontSize: Style.font.caption
								selected: root.settingShowCompleted === "off"
								onClicked: root.settingShowCompleted = "off"
							}

							Button {
								width: 80
								text: "On"
								foreground: root.settingShowCompleted === "on" ? root.themeAccent : root.themeMuted
								fontSize: Style.font.caption
								selected: root.settingShowCompleted === "on"
								onClicked: root.settingShowCompleted = "on"
							}
						}
					}
				}

				Rectangle {
					width: 1
					height: 1
					color: root.lineColor
				}

				// Save / Cancel buttons
				Row {
					width: parent.width
					spacing: Style.space(6)

					Button {
						width: 80
						text: "Cancel"
						foreground: root.themeFg
						onClicked: root.showSettings = false
					}

					Button {
						width: parent.width - 80
						text: "Save changes"
						foreground: root.themeAccent
						selected: true
						bordered: true
						onClicked: root.saveAllSettings()
					}
				}
			}
		}
	}
}

// Local state for expanded task time picker
property bool showTimePicker: false
