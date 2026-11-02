import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const menus = vm.createContext({});
vm.runInContext(readFileSync(new URL("../../nix/modules/desktop/quickshell/DesktopMenus.js", import.meta.url), "utf8"), menus);

test("power confirmation starts with cancel and permits only fixed actions", () => {
    for (const action of menus.entries("power", "")) {
        if (action.id === "lock") {
            assert.equal(action.confirm, undefined);
            continue;
        }
        assert.equal(action.confirm, true);
        const confirmation = menus.entries("confirm", action.id);
        assert.equal(confirmation[0].kind, "back");
        assert.equal(confirmation[1].confirm, undefined);
        assert.equal(confirmation[1].args[1], action.id);
    }
    assert.equal(menus.entries("confirm", "shutdown; touch /tmp/no").length, 0);
});

test("clipboard previews remain text and only numeric IDs become arguments", () => {
    const rows = menus.clipboardEntries("42\t$(touch /tmp/no)\nnot-an-id\tbad\n73\timage preview\n");
    assert.equal(rows.length, 2);
    assert.equal(rows[0].name, "$(touch /tmp/no)");
    assert.equal(JSON.stringify(rows[0].args), '["clipboard-copy","42"]');
});

test("notification history preserves bodies as display text, not actions", () => {
    const rows = menus.notificationEntries(JSON.stringify([
        { id: 1, summary: "Test", body: "<b>Literal body</b>", app_name: "Test app" },
        { id: 2, summary: null, body: null, app_icon: null }
    ]));
    assert.equal(rows[0].body, "<b>Literal body</b>");
    assert.equal(rows[0].kind, "notification");
    assert.equal(rows[0].args, undefined);
    assert.equal(rows[1].name, "Notification");
    assert.equal(rows[1].body, "");
    assert.throws(() => menus.notificationEntries("invalid"));
});
