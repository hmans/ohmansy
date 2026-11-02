// Niri's event stream starts with full snapshots, then sends incremental updates.
function update(state, event) {
    var workspaces = state.workspaces;
    var windows = state.windows;
    if (event.WorkspacesChanged) workspaces = event.WorkspacesChanged.workspaces;
    if (event.WindowsChanged) windows = event.WindowsChanged.windows;
    if (event.WorkspaceActivated) {
        var activation = event.WorkspaceActivated;
        var workspace = workspaces.find(function(w) { return w.id === activation.id; });
        if (workspace) workspaces = workspaces.map(function(w) {
            return Object.assign({}, w, {
                is_active: w.output === workspace.output ? w.id === workspace.id : w.is_active,
                is_focused: activation.focused ? w.id === workspace.id : w.is_focused
            });
        });
    }
    if (event.WorkspaceActiveWindowChanged) workspaces = workspaces.map(function(w) {
        return w.id === event.WorkspaceActiveWindowChanged.workspace_id
            ? Object.assign({}, w, { active_window_id: event.WorkspaceActiveWindowChanged.active_window_id }) : w;
    });
    if (event.WorkspaceUrgencyChanged) workspaces = workspaces.map(function(w) {
        return w.id === event.WorkspaceUrgencyChanged.id
            ? Object.assign({}, w, { is_urgent: event.WorkspaceUrgencyChanged.urgent }) : w;
    });
    if (event.WindowOpenedOrChanged) {
        var window = event.WindowOpenedOrChanged.window;
        windows = windows.filter(function(w) { return w.id !== window.id; }).map(function(w) {
            return window.is_focused ? Object.assign({}, w, { is_focused: false }) : w;
        }).concat([window]);
    }
    if (event.WindowClosed) windows = windows.filter(function(w) { return w.id !== event.WindowClosed.id; });
    if (event.WindowLayoutsChanged) windows = windows.map(function(w) {
        var change = event.WindowLayoutsChanged.changes.find(function(c) { return c[0] === w.id; });
        return change ? Object.assign({}, w, { layout: change[1] }) : w;
    });
    if (event.WindowFocusChanged) windows = windows.map(function(w) {
        return Object.assign({}, w, { is_focused: w.id === event.WindowFocusChanged.id });
    });
    return { workspaces: workspaces, windows: windows };
}
function workspacesFor(state, output) {
    return state.workspaces.filter(function(w) { return w.output === output; })
        .sort(function(a, b) { return a.idx - b.idx; });
}
function titleFor(state, output) {
    var workspace = state.workspaces.find(function(w) { return w.output === output && w.is_active; });
    var window = workspace && state.windows.find(function(w) { return w.id === workspace.active_window_id; });
    return window ? (window.title || window.app_id || "") : "";
}
function shortTitle(title) {
    return title.replace(/( - | — | – )(Google Chrome|Chromium|Mozilla Firefox|Visual Studio Code)$/, "");
}
