pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "calc.js" as Calc

// The app launcher: state, search and actions. components/LauncherWindow.qml
// draws `results` and calls activate().
//
// Modes:
//   "all"    apps, open windows, a calculator answer and power actions typed
//            out (3+ letters); a query starting with ";" lists clipboard history
//   "power"  just the five power actions (the ⏻ button)
Singleton {
    id: root

    property bool open: false
    property string mode: "all"
    property string query: ""
    property string screenName: ""
    // The card's left edge and horizontal pill center in screen coordinates.
    property real anchorX: 0
    property real anchorCenterX: -1
    // Horizontal cutout span (including concave wings) and card shape reported to
    // FrameHost so the top frame hairline and inward shadow stay clean around an
    // attached Launcher drawer. LauncherWindow writes them for as long as its
    // card is on screen, which is a little longer than `open`: the card
    // retracts into the lip after closing.
    property real activeCutLeft: 0
    property real activeCutRight: 0
    property real activeCutX: 0
    property real activeCutWidth: 0
    property real activeCutHeight: 0
    property real activeCutRadius: 0
    property real activeCutWing: 0
    // An action waiting for its confirming second Enter or click, or "", and
    // when it began to wait (ms since 1970).
    property string armed: ""
    property real armedAt: 0

    // Each bar's launcher pill, so a keyboard shortcut can still drop the card
    // from the pill on the focused screen.
    property var pills: ({})

    // ── Opening and closing ────────────────────────────────────────────────

    function registerPill(screenName, item) {
        const next = Object.assign({}, root.pills);
        next[screenName] = item;
        root.pills = next;
    }

    function anchorFor(item) {
        try {
            return item.mapToItem(null, 0, 0).x + Theme.barMarginSide;
        } catch (e) {
            return Theme.barMarginSide + Theme.barPadding;
        }
    }

    function anchorCenterFor(item) {
        try {
            return item.mapToItem(null, item.width / 2, 0).x + Theme.barMarginSide;
        } catch (e) {
            return -1;
        }
    }

    // A click on a pill: open on that bar's screen, under `item`.
    function toggleFrom(screenName, item, mode) {
        root.show(screenName, root.anchorFor(item), mode, "", root.anchorCenterFor(item));
    }

    // A shortcut (IPC): the focused screen, under its launcher pill when shown.
    function toggleOnFocused(mode, query) {
        const name = Popups.focusedScreenName();
        const pill = root.pills[name];
        const visiblePill = pill && !BarConfig.isHidden("launcher");
        const x = visiblePill ? root.anchorFor(pill) : Theme.barMarginSide + Theme.barPadding;
        const cx = visiblePill ? root.anchorCenterFor(pill) : -1;
        root.show(name, x, mode, query, cx);
    }

    // Pressing the same thing again closes: same screen, same mode, and
    // clipboard-or-not unchanged.
    function show(screenName, x, mode, query, centerX) {
        const sameKind = (root.query.indexOf(";") === 0) === (query === ";");
        if (root.open && root.mode === mode && root.screenName === screenName && sameKind) {
            root.close();
            return;
        }
        Popups.close();
        // Before the mode changes: that rebuilds the list, and the window keeps
        // an armed action selected through a rebuild.
        root.unarm();
        root.screenName = screenName;
        root.anchorX = x;
        root.anchorCenterX = (centerX !== undefined && centerX !== null) ? centerX : -1;
        root.mode = mode;
        root.query = query;
        root.open = true;
    }

    // anchorCenterX stays as it is: the card is still under its pill while it
    // retracts, and show() sets it afresh.
    function close() {
        root.open = false;
        root.query = "";
        root.unarm();
    }

    Connections {
        target: BarConfig
        function onLookChanged() {
            root.close();
        }
    }

    Connections {
        target: Compositor
        function onFullscreenChanged(output, isFullscreen) {
            if (isFullscreen && root.open && root.screenName === output)
                root.close();
        }
    }

    // Typing withdraws a confirmation that was pending.
    onQueryChanged: root.unarm()

    // ── Matching ───────────────────────────────────────────────────────────
    // 100 exact, 90 prefix, 75 word start, 60 substring, 1..40 for the letters
    // in order with gaps (fewer gaps score higher), 0 no match. `q` is lowercase.
    function matchScore(q, text) {
        if (!text)
            return 0;
        const t = String(text).toLowerCase();
        if (t === q)
            return 100;
        if (t.indexOf(q) === 0)
            return 90;
        let idx = t.indexOf(q);
        if (idx !== -1) {
            while (idx !== -1) {
                if (!/[a-z0-9]/.test(t[idx - 1]))
                    return 75;
                idx = t.indexOf(q, idx + 1);
            }
            return 60;
        }
        let i = 0;
        let last = -1;
        let gaps = 0;
        for (let j = 0; j < t.length && i < q.length; j++) {
            if (t[j] === q[i]) {
                if (last >= 0)
                    gaps += j - last - 1;
                last = j;
                i++;
            }
        }
        return (i < q.length) ? 0 : Math.max(1, 40 - gaps);
    }

    // ── Results ────────────────────────────────────────────────────────────
    // Row: { kind, key, title, subtitle, icon, glyph, … } where kind is one of
    // "app" (entry), "window" (windowId), "calc" (value), "clip" (clipId),
    // "clipaction" (action: pausing or clearing the history), "power" (action)
    // or "info" (not activatable).
    readonly property var results: root.open ? root.compute() : []

    function compute() {
        if (root.mode === "power")
            return root.powerActions.map(root.powerRow);
        const raw = root.query;
        if (raw.indexOf(";") === 0)
            return root.clipRows(raw.slice(1).trim().toLowerCase());
        const q = raw.trim().toLowerCase();
        let out = [];
        const calc = root.calcRow(raw.trim());
        if (calc)
            out.push(calc);
        out = out.concat(root.appRows(q));
        if (q !== "")
            out = out.concat(root.windowRows(q), root.powerMatches(q));
        return out.slice(0, 30);
    }

    function appRows(q) {
        const apps = DesktopEntries.applications.values;
        const scored = [];
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i];
            let s;
            if (q === "") {
                s = 1;
            } else {
                s = Math.max(root.matchScore(q, e.name),
                    0.8 * root.matchScore(q, e.genericName),
                    0.6 * root.matchScore(q, e.id));
                const keywords = Array.from(e.keywords || []);
                for (let k = 0; k < keywords.length; k++)
                    s = Math.max(s, 0.7 * root.matchScore(q, keywords[k]));
            }
            if (s <= 0)
                continue;
            const uses = root.counts[e.id] || 0;
            scored.push({ entry: e, score: s + 1.5 * Math.min(uses, 20), uses: uses });
        }
        scored.sort((a, b) => (b.score - a.score) || a.entry.name.localeCompare(b.entry.name));
        return scored.slice(0, 8).map((x) => ({
            kind: "app", key: "app:" + x.entry.id, title: x.entry.name,
            subtitle: x.entry.genericName || x.entry.comment || "",
            icon: x.entry.icon || "", glyph: "", entry: x.entry
        }));
    }

    function windowRows(q) {
        const wins = Compositor.windows;
        const scored = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            const s = Math.max(0.9 * root.matchScore(q, w.title), 0.8 * root.matchScore(q, w.app_id));
            if (s > 0)
                scored.push({ w: w, score: s });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.slice(0, 4).map((x) => {
            const entry = x.w.app_id ? DesktopEntries.heuristicLookup(x.w.app_id) : null;
            return {
                kind: "window", key: "win:" + x.w.id, windowId: x.w.id,
                title: x.w.title || x.w.app_id || "Window",
                subtitle: "Window · " + (entry ? entry.name : (x.w.app_id || "")),
                icon: entry ? (entry.icon || "") : "", glyph: "\uf2d0"
            };
        });
    }

    function calcRow(text) {
        let expr = text;
        if (expr.indexOf("=") === 0)
            expr = expr.slice(1);
        else if (!/[0-9]/.test(expr) || !/[+\-*/%^]/.test(expr))
            return null;
        const answer = Calc.evaluate(expr);
        if (answer === null)
            return null;
        const shown = Calc.format(answer);
        // Copying goes through the clipboard history's helper job.
        const copies = ClipboardHistory.active ? "Enter copies"
            : ClipboardHistory.installed ? "can't copy: clipboard history is not running"
            : "copying needs skua-helper";
        return {
            kind: "calc", key: "calc", title: shown,
            subtitle: expr.trim() + "  ·  " + copies, icon: "", glyph: "\uf1ec", value: shown
        };
    }

    readonly property var powerActions: [
        { key: "lock", title: "Lock", glyph: 0xF023, confirm: false },
        { key: "suspend", title: "Suspend", glyph: 0xF0904, confirm: false },
        { key: "logout", title: "Log out", glyph: 0xF0343, confirm: true },
        { key: "reboot", title: "Reboot", glyph: 0xF0709, confirm: true },
        { key: "poweroff", title: "Power off", glyph: 0xF011, confirm: true }
    ]

    // A row is the same whether or not its action is waiting for the second
    // Enter: LauncherRow adds "again to confirm" from `armed` itself. If the
    // title were built from `armed` here, every arming and disarming would
    // rebuild `results`, and a rebuilt list is where a selection gets lost.
    function powerRow(p) {
        const viaSwaylock = p.key === "suspend" || (p.key === "lock" && !root.hyprlock());
        return {
            kind: "power", key: "power:" + p.key, action: p.key,
            title: p.title,
            subtitle: (viaSwaylock && !Programs.has("swaylock"))
                ? "swaylock not found: uses loginctl lock-session" : "",
            icon: "", glyph: String.fromCodePoint(p.glyph)
        };
    }

    // Lock uses hyprlock on Hyprland when it is installed.
    function hyprlock() {
        return Compositor.isHyprland && Programs.has("hyprlock");
    }

    // In "all" mode a power action only appears once 3+ letters start its name,
    // and always after apps and windows, so it is never the accidental first row.
    function powerMatches(q) {
        if (q.length < 3)
            return [];
        return root.powerActions
            .filter((p) => p.title.toLowerCase().indexOf(q) === 0)
            .map(root.powerRow);
    }

    // ── Clipboard history (ClipboardHistory, skua-helper clipboard) ────────
    // The rows follow the history as it changes, also while the card is open.

    function clipRows(q) {
        const info = root.clipInfo();
        if (info !== null)
            return [info];
        const rows = [];
        const items = ClipboardHistory.items;
        for (let i = 0; i < items.length && rows.length < 50; i++) {
            const c = items[i];
            if (q !== "" && c.preview.toLowerCase().indexOf(q) === -1)
                continue;
            const image = c.kind === "image";
            rows.push({
                kind: "clip", key: "clip:" + c.id, clipId: c.id,
                title: image ? "Image" : (c.preview || "Blank text"),
                subtitle: image ? root.imageSubtitle(c) : "",
                icon: "", glyph: image ? "\uf03e" : "\uf0ea"
            });
        }
        // The history's own controls come after its entries (Up from the first
        // row reaches them), and only for the whole list, not in a search. An
        // empty history starts with a row Enter does nothing on, so Enter on a
        // bare ";" never pauses or clears by accident.
        if (q !== "")
            return rows;
        if (items.length === 0)
            rows.push(root.clipNote("info:clip-empty", "Nothing copied yet",
                ClipboardHistory.paused ? "The history is paused" : "Texts and images you copy appear here"));
        rows.push({
            kind: "clipaction", key: "clipaction:pause", action: "clip-pause",
            title: ClipboardHistory.paused ? "Resume clipboard history" : "Pause clipboard history",
            subtitle: ClipboardHistory.paused ? "Paused: new copies are not kept"
                : "Keep no new copies until you resume",
            icon: "", glyph: ClipboardHistory.paused ? "\uf04b" : "\uf04c"
        });
        if (items.length > 0)
            rows.push({
                kind: "clipaction", key: "clipaction:clear", action: "clip-clear",
                title: "Clear clipboard history",
                subtitle: "Deletes all " + items.length + " entries; Shift+Delete removes only the selected one",
                icon: "", glyph: "\uf1f8"
            });
        return rows;
    }

    // Shift+Delete on an entry: it goes from the history and from the disk.
    function removeClip(row) {
        if (row && row.kind === "clip")
            ClipboardHistory.remove(row.clipId);
    }

    // Pausing switches at once and the card stays open, so the row shows the
    // new state. Clearing everything needs a second Enter or click within 3 s,
    // as Reboot does.
    function runClipAction(action) {
        if (action === "clip-pause") {
            ClipboardHistory.setPaused(!ClipboardHistory.paused);
        } else if (action === "clip-clear") {
            if (!root.confirmed(action))
                return;
            root.unarm();
            ClipboardHistory.clear();
        }
    }

    // Why there is no history to show, or null when there is one.
    function clipInfo() {
        if (!ClipboardHistory.installed)
            return root.clipNote("info:clip", "Clipboard history needs skua-helper",
                "Install it from Skua's folder: " + SkuaHelper.installCommand);
        if (ClipboardHistory.active)
            return null;
        if (ClipboardHistory.outdated)
            return root.clipNote("info:clip", "skua-helper is too old for clipboard history",
                "Reinstall it from Skua's folder: " + SkuaHelper.installCommand);
        return root.clipNote("info:clip", "Clipboard history is not running",
            ClipboardHistory.problem || "skua-helper clipboard is starting");
    }

    function clipNote(key, title, subtitle) {
        return { kind: "info", key: key, title: title, subtitle: subtitle, icon: "", glyph: "\uf0ea" };
    }

    // "PNG · 1920×1080 · 1.4 MB"
    function imageSubtitle(c) {
        const parts = [c.mime.replace(/^image\//, "").toUpperCase()];
        if (c.width > 0 && c.height > 0)
            parts.push(c.width + "×" + c.height);
        if (c.size >= 1024 * 1024)
            parts.push((c.size / (1024 * 1024)).toFixed(1) + " MB");
        else
            parts.push(Math.max(1, Math.round(c.size / 1024)) + " KB");
        return parts.join(" · ");
    }

    // ── Usage counts (apps you launch often rise to the top) ──────────────
    property var counts: ({})

    FileView {
        id: usageFile
        path: BarConfig.stateDir + "/launcher.json"
        printErrors: false

        onLoaded: {
            try {
                const o = JSON.parse(usageFile.text());
                root.counts = (o && o.counts && typeof o.counts === "object") ? o.counts : {};
            } catch (e) {
                root.counts = {};
            }
        }
    }

    function bump(id) {
        const next = Object.assign({}, root.counts);
        next[id] = Math.min(1000, (next[id] || 0) + 1);
        root.counts = next;
        usageFile.setText(JSON.stringify({ counts: next }) + "\n");
    }

    // ── Actions ────────────────────────────────────────────────────────────

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = ""
    }

    // Withdraw a pending confirmation: the selection or the search moved on, or
    // the launcher is being opened afresh or closed.
    function unarm() {
        root.armed = "";
        disarm.stop();
    }

    // Whether this Enter or click on `action` confirms it. The first one only
    // arms it. A later one confirms, unless it follows the arming within a
    // double-click's time: both clicks of a double-click reach the row, and a
    // double-click is one gesture, not a decision made twice. The action stays
    // armed then, so one more Enter or click confirms it.
    function confirmed(action) {
        if (root.armed !== action) {
            root.armed = action;
            root.armedAt = Date.now();
            disarm.restart();
            return false;
        }
        return Date.now() - root.armedAt >= Qt.styleHints.mouseDoubleClickInterval;
    }

    function activate(row) {
        if (!row)
            return;
        if (row.kind === "app") {
            // The compositor opens new windows on the focused output.
            Compositor.focusMonitor(root.screenName);
            if (row.entry.runInTerminal && Programs.terminal !== "")
                Quickshell.execDetached({
                    command: Programs.terminalCommand(row.entry.command),
                    workingDirectory: row.entry.workingDirectory
                });
            else
                row.entry.execute();
            root.bump(row.entry.id);
            root.close();
        } else if (row.kind === "window") {
            Compositor.focusWindow(row.windowId);
            root.close();
        } else if (row.kind === "calc") {
            ClipboardHistory.copyText(row.value);
            root.close();
        } else if (row.kind === "clip") {
            ClipboardHistory.copy(row.clipId);
            root.close();
        } else if (row.kind === "clipaction") {
            root.runClipAction(row.action);
        } else if (row.kind === "power") {
            root.runPower(row.action);
        }
    }

    // Log out, Reboot and Power off need a second Enter (or click) within 3 s.
    function runPower(key) {
        const p = root.powerActions.find((a) => a.key === key);
        if (!p)
            return;
        if (p.confirm && !root.confirmed(key))
            return;
        root.close();
        const color = Theme.card.toString().slice(1, 7);
        const lock = Programs.has("swaylock")
            ? ["swaylock", "-f", "-c", color] : ["loginctl", "lock-session"];
        // hyprlock stays in the foreground until unlocked, so it locks but is
        // never the lock in front of a suspend.
        if (key === "lock")
            Quickshell.execDetached(root.hyprlock() ? ["hyprlock"] : lock);
        else if (key === "suspend")
            Quickshell.execDetached(["sh", "-c", "\"$@\" && systemctl suspend", "sh"].concat(lock));
        else if (key === "logout")
            Compositor.quit();
        else if (key === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (key === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }
}
