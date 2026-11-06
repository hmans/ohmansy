.pragma library

// Stable IDs and keywords are independent of UI labels and execution details.
var desktop = { id: "desktop", items: [
    { id: "desktop:displays", title: "Displays", subtitle: "Resolution, scale and refresh rate", icon: "preferences-desktop-display-symbolic", keywords: ["monitor", "screen", "settings"], command: "displays" },
    { id: "desktop:terminal", title: "Open Terminal", subtitle: "Start a terminal", icon: "utilities-terminal-symbolic", keywords: ["shell", "console"], command: "terminal" },
    { id: "desktop:dark", title: "Dark Mode", subtitle: "Use dark appearance", icon: "weather-clear-night-symbolic", keywords: ["theme", "appearance", "night"], command: "prefer-dark" },
    { id: "desktop:light", title: "Light Mode", subtitle: "Use light appearance", icon: "weather-clear-symbolic", keywords: ["theme", "appearance", "day"], command: "prefer-light" }
].map(item => Object.assign({ provider: "desktop" }, item)) };
