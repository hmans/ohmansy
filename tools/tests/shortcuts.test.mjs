import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const shortcuts = vm.createContext({});
vm.runInContext(readFileSync(new URL("../../nix/modules/desktop/quickshell/Shortcuts.js", import.meta.url), "utf8"), shortcuts);
const groups = JSON.parse(readFileSync(new URL("../../nix/modules/desktop/shortcuts.json", import.meta.url), "utf8"));

test("shortcut definitions have unique keys and complete help metadata", () => {
    const bindings = groups.flatMap(group => group.bindings);
    assert.equal(new Set(bindings.map(binding => binding.key)).size, bindings.length);
    for (const group of groups) {
        assert.ok(group.title);
        for (const binding of group.bindings) {
            assert.ok(binding.title && binding.action && binding.key);
            assert.ok(!binding.key.includes("\n"));
        }
    }
    assert.equal(bindings.find(binding => binding.key === "Mod+Shift+Slash").action,
        'spawn "ohmansy-desktop" "menu" "shortcuts"');
});

test("help groups aliases without losing any bindings", () => {
    const sections = shortcuts.sections(groups, "");
    assert.equal(sections.flatMap(section => section.rows).flatMap(row => row.keys).length,
        groups.flatMap(group => group.bindings).length);
    const close = sections.flatMap(section => section.rows).find(row => row.title === "Close window");
    assert.equal(close.keys.length, 2);
    const keys = groups.flatMap(group => group.bindings).map(binding => binding.key);
    assert.ok(!keys.includes("Mod+T") && !keys.includes("Mod+B"));
});

test("search matches actions, categories, and displayed keys", () => {
    const rows = query => shortcuts.sections(groups, query).flatMap(section => section.rows);
    assert.ok(rows("super enter").some(row => row.title === "Open terminal"));
    assert.ok(rows("volume").some(row => row.title === "Volume up"));
    assert.ok(rows("window layout").length > 0);
    assert.equal(rows("no-such-shortcut").length, 0);
    assert.equal(JSON.stringify(shortcuts.keycaps("Mod+Shift+Left")), '["Super","Shift","←"]');
});
