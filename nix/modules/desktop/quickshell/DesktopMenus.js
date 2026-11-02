// Only fixed action identifiers become helper arguments. Labels are display text.
var power = [
    { id: "lock", name: "Lock", icon: "system-lock-screen-symbolic" },
    { id: "logout", name: "Log out", icon: "system-log-out-symbolic", confirm: true },
    { id: "suspend", name: "Suspend", icon: "weather-clear-night-symbolic", confirm: true },
    { id: "reboot", name: "Restart", icon: "system-reboot-symbolic", confirm: true },
    { id: "shutdown", name: "Shut down", icon: "system-shutdown-symbolic", confirm: true }
];
function entries(mode, pending) {
    if (mode === "power") return power.map(function(item) {
        return Object.assign({ kind: "action", args: ["power-action", item.id] }, item);
    });
    if (mode === "confirm") {
        var action = power.find(function(item) { return item.id === pending && item.confirm; });
        return action ? [
            { kind: "back", name: "Cancel", icon: "go-previous-symbolic" },
            { kind: "action", name: "Confirm " + action.name.toLowerCase(), icon: action.icon,
                args: ["power-action", action.id] }
        ] : [];
    }
    if (mode === "controls") return [
        { id: "sound", name: "Sound", icon: "audio-volume-high-symbolic" },
        { id: "network", name: "Network", icon: "network-wired-symbolic" },
        { id: "bluetooth", name: "Bluetooth", icon: "bluetooth-symbolic" },
        { id: "wallpaper", name: "Choose wallpaper image", icon: "preferences-desktop-wallpaper-symbolic" },
        { id: "ribbons", name: "Use animated ribbons", icon: "preferences-desktop-wallpaper-symbolic" }
    ].map(function(item) { return Object.assign({ kind: "action", args: ["control-action", item.id] }, item); });
    return [];
}
function clipboardEntries(text) {
    return text.split("\n").filter(function(line) { return /^\d+\t/.test(line); }).map(function(line) {
        var separator = line.indexOf("\t");
        return { kind: "action", id: line.slice(0, separator),
            name: line.slice(separator + 1).replace(/[\u0000-\u001f\u007f]/g, " "),
            icon: "edit-paste-symbolic", args: ["clipboard-copy", line.slice(0, separator)] };
    });
}
function notificationEntries(text) {
    return JSON.parse(text).map(function(item) {
        return { kind: "notification", id: item.id, name: item.summary || "Notification",
            comment: item.app_name || "", body: item.body || "",
            icon: item.app_icon || "preferences-system-notifications-symbolic" };
    });
}
