# SingularityApp Plugin for Omarchy

**View and manage SingularityApp tasks from the Omarchy bar.** Wears every Omarchy theme.

![SingularityApp plugin](https://api.singularity-app.com/v2/logo?light=dark)

## Overview

The SingularityApp plugin integrates [SingularityApp](https://singularity-app.com) with your Omarchy workflow. It provides:

- **Bar widget**: Shows today's open task count in the Omarchy bar
- **Floating panel**: Full daily task planner with create, edit, and completion actions
- **API integration**: Connects to the SingularityApp v2 REST API

## Features

### Bar Widget

- Displays task count as an icon in the Omarchy bar
- Click to open the task panel
- Right-click to toggle the panel
- Tooltip shows task count or status
- Shows "no tasks" / "loading" / "no API token" states

### Task Panel

- **Today's task list** with overdue indicator
- **Quick add** form with title, note, project, tags, priority, date, and time
- **Task actions** per row:
  - Complete/Reopen checkbox
  - Expand/collapse ▼ button
  - Priority color coding
  - Time display
- **Expanded task view** with action buttons:
  - Done/Reopen
  - Tomorrow (postpone)
  - Cancel
  - Schedule at specific time
  - Delete task
- **Project and tag** filtering and display

### API Integration

- Polls `https://api.singularity-app.com/v2` for tasks
- Supports Bearer token authentication
- Auto-refresh at configurable intervals (default: 5 minutes)
- Loads projects and tags on startup

## Installation

1. Place the `david.singularity` directory in your Omarchy plugins directory
   ```bash
   # Typical location
   ~/.config/omarchy/plugins/david.singularity/
   ```

2. Ensure the plugin is loaded in your Omarchy configuration

3. Restart Omarchy or reload plugins

## Configuration

The plugin accepts these settings (configure via `omarchy bar set` or the panel UI):

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `apiToken` | password | `""` | Your SingularityApp v2 API token (Bearer) |
| `refreshMinutes` | integer | `5` | How often the bar widget polls the API (1-60) |
| `showCompleted` | enum | `off` | Show completed tasks in the list |
| `maxTasks` | integer | `20` | Maximum tasks shown in the list (5-100) |

### Set API Token

```bash
omarchy bar set david.singularity apiToken YOUR_TOKEN_HERE
```

## Usage

### Summon the panel

```bash
omarchy-shell shell summon david.singularity '{}'
```

### Bar widget interactions

- **Left-click**: Open the task panel
- **Right-click**: Toggle the panel open/closed

### Panel actions

- **Quick add**: Click `+` or press Enter to quickly add a task
- **Complete task**: Click the checkbox or "Done" button
- **Postpone**: Click "Tomorrow" to move to next day
- **Cancel**: Click "Cancel" to delete (move to trash)
- **Schedule**: Select a time preset or open the time picker
- **Delete**: Click "Delete task" in expanded view

## Development

### Plugin Structure

```
david.singularity/
├── manifest.json     # Plugin metadata and configuration schema
├── Plugin.qml        # Plugin entry point, signals and service delegation
├── BarWidget.qml     # Omarchy bar widget (task count display)
├── Panel.qml         # Floating task panel UI
└── Service.qml       # Background API service and task management
```

### API Endpoints

The service communicates with `https://api.singularity-app.com/v2`:

- `GET /task?includeRemoved=false&includeArchived=false&maxCount=N` - Fetch tasks
- `GET /project?maxCount=100` - Load projects
- `GET /tag?maxCount=200` - Load tags
- `POST /task` - Create a new task
- `PATCH /task/{id}` - Update a task (complete, uncomplete, postpone, schedule, delete)
- `DELETE /task/{id}` - Delete a task

### Authentication

Set your API token via:
- `omarchy bar set david.singularity apiToken YOUR_TOKEN`
- Or enter it in the panel's API token setup area

### Building from Source

No build step required - QML files are interpreted at runtime. Modify QML files directly and reload the plugin.

## License

MIT - Copyright (c) david

## References

- SingularityApp API: https://api.singularity-app.com/v2
- Omarchy documentation: https://omarchy.dev