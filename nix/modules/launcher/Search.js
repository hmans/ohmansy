.pragma library

// Prefer exact names, prefixes and word boundaries over scattered letters.
function score(text, query) {
    text = text.toLowerCase();
    if (text === query) return 10000;
    if (text.startsWith(query)) return 8000 - text.length;
    const substring = text.indexOf(query);
    if (substring >= 0) return 6000 - substring * 10 - text.length;
    let previous = -1;
    let value = 0;
    for (let i = 0; i < query.length; i++) {
        const position = text.indexOf(query[i], previous + 1);
        if (position < 0) return -1;
        value += 20;
        if (position === 0 || /[\s._/-]/.test(text[position - 1])) value += 35;
        if (position === previous + 1) value += 15;
        value -= position - previous - 1;
        previous = position;
    }
    return Math.max(0, value);
}

function rank(items, input) {
    const words = input.trim().toLowerCase().split(/\s+/).filter(Boolean);
    return items.map(item => {
        let total = 0;
        for (const word of words) {
            const name = score(item.title, word);
            const keywords = score((item.keywords || []).join(" "), word);
            const best = Math.max(name, keywords < 0 ? -1 : keywords * 0.45);
            if (best < 0) return { item: item, score: -1 };
            total += best;
        }
        return { item: item, score: total };
    }).filter(result => result.score >= 0).sort((a, b) =>
        b.score - a.score || a.item.title.localeCompare(b.item.title) || a.item.id.localeCompare(b.item.id)
    ).map(result => result.item);
}
