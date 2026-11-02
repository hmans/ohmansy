function keycaps(key) {
    const names = { Mod: "Super", Return: "Enter", Slash: "/", Comma: ",",
        Minus: "−", Equal: "=", Page_Up: "PgUp", Page_Down: "PgDn",
        Left: "←", Right: "→", Up: "↑", Down: "↓", Print: "PrtSc",
        XF86AudioRaiseVolume: "Volume +", XF86AudioLowerVolume: "Volume −",
        XF86AudioMute: "Mute", XF86AudioMicMute: "Mic mute",
        XF86AudioPlay: "Play", XF86AudioNext: "Next", XF86AudioPrev: "Previous" };
    return key.split("+").map(key => names[key] || key);
}

function sections(groups, query) {
    const words = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
    return groups.map((group, index) => {
        const rows = [];
        group.bindings.forEach(binding => {
            let row = rows.find(row => row.action === binding.action);
            if (!row) {
                row = { title: binding.title, action: binding.action, keys: [] };
                rows.push(row);
            }
            row.keys.push(binding.key);
        });
        return { title: group.title, column: index === 2 || index === 4 ? 1 : 0,
            rows: rows.filter(row => {
                const text = [group.title, row.title, ...row.keys,
                    row.keys.map(key => keycaps(key).join(" ")).join(" ")].join(" ").toLowerCase();
                return words.every(word => text.includes(word));
            }) };
    }).filter(group => group.rows.length);
}
