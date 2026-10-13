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
    // The card's left edge in screen coordinates: under the pill it came from.
    property real anchorX: 0
    // A power action waiting for its confirming second Enter, or "".
    property string armed: ""

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

    // A click on a pill: open on that bar's screen, under `item`.
    function toggleFrom(screenName, item, mode) {
        root.show(screenName, root.anchorFor(item), mode, "");
    }

    // A shortcut (IPC): the focused screen, under its launcher pill when shown.
    function toggleOnFocused(mode, query) {
        const name = Popups.focusedScreenName();
        const pill = root.pills[name];
        const x = (pill && !BarConfig.isHidden("launcher"))
            ? root.anchorFor(pill) : Theme.barMarginSide + Theme.barPadding;
        root.show(name, x, mode, query);
    }

    // Pressing the same thing again closes: same screen, same mode, and
    // clipboard-or-not unchanged.
    function show(screenName, x, mode, query) {
        const sameKind = (root.query.indexOf(";") === 0) === (query === ";");
        if (root.open && root.mode === mode && root.screenName === screenName && sameKind) {
            root.close();
            return;
        }
        Popups.close();
        root.screenName = screenName;
        root.anchorX = x;
        root.mode = mode;
        root.armed = "";
        root.query = query;
        root.open = true;
    }

    function close() {
        root.open = false;
        root.query = "";
        root.armed = "";
        root.clipsLoaded = false;
    }

    onQueryChanged: {
        if (root.open && root.query.indexOf(";") === 0 && !root.clipsLoaded)
            root.loadClips();
    }
    onOpenChanged: {
        if (root.open && root.query.indexOf(";") === 0 && !root.clipsLoaded)
            root.loadClips();
    }

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
    // "power" (action) or "info" (not activatable).
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
        const wins = Niri.windows;
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
        const v = Calc.evaluate(expr);
        if (v === null)
            return null;
        const shown = Calc.format(v);
        return {
            kind: "calc", key: "calc", title: shown,
            subtitle: expr.trim() + "  ·  Enter copies", icon: "", glyph: "\uf1ec", value: shown
        };
    }

    readonly property var powerActions: [
        { key: "lock", title: "Lock", glyph: 0xF023, confirm: false },
        { key: "suspend", title: "Suspend", glyph: 0xF0904, confirm: false },
        { key: "logout", title: "Log out", glyph: 0xF0343, confirm: true },
        { key: "reboot", title: "Reboot", glyph: 0xF0709, confirm: true },
        { key: "poweroff", title: "Power off", glyph: 0xF011, confirm: true }
    ]

    function powerRow(p) {
        const armed = root.armed === p.key;
        return {
            kind: "power", key: "power:" + p.key, action: p.key,
            title: armed ? p.title + " — again to confirm" : p.title,
            subtitle: ((p.key === "lock" || p.key === "suspend") && !Programs.has("swaylock"))
                ? "swaylock not found: uses loginctl lock-session" : "",
            icon: "", glyph: String.fromCodePoint(p.glyph)
        };
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

    // ── Clipboard history (cliphist) ───────────────────────────────────────
    property var clips: []          // [{ id, text }], newest first
    property bool clipsLoaded: false
    property bool clipsFailed: false
    property string clipBuffer: ""

    function loadClips() {
        if (clipProc.running || !Programs.has("cliphist"))
            return;
        root.clipBuffer = "";
        clipProc.running = true;
    }

    Process {
        id: clipProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: (line) => root.clipBuffer += line + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            const out = [];
            const lines = root.clipBuffer.split("\n");
            for (let i = 0; i < lines.length; i++) {
                const tab = lines[i].indexOf("\t");
                if (tab > 0)
                    out.push({ id: lines[i].slice(0, tab), text: lines[i].slice(tab + 1) });
            }
            root.clipBuffer = "";
            root.clipsFailed = exitCode !== 0;
            root.clips = out;
            root.clipsLoaded = true;
        }
    }

    function clipRows(q) {
        if (!Programs.has("cliphist") || !Programs.has("wl-copy") || root.clipsFailed) {
            return [{
                kind: "info", key: "info:clip", title: "Clipboard history needs cliphist",
                subtitle: "and wl-clipboard, with `wl-paste --watch cliphist store` running",
                icon: "", glyph: "\uf0ea"
            }];
        }
        const rows = [];
        for (let i = 0; i < root.clips.length && rows.length < 50; i++) {
            const c = root.clips[i];
            if (q !== "" && c.text.toLowerCase().indexOf(q) === -1)
                continue;
            const image = c.text.indexOf("[[ binary data") === 0;
            rows.push({
                kind: "clip", key: "clip:" + c.id, clipId: c.id,
                title: image ? "Image" : c.text.replace(/\s+/g, " "),
                subtitle: image ? c.text.replace(/^\[\[ binary data\s*/, "").replace(/\s*\]\]$/, "") : "",
                icon: "", glyph: image ? "\uf03e" : "\uf0ea"
            });
        }
        return rows;
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

    function activate(row) {
        if (!row)
            return;
        if (row.kind === "app") {
            // niri opens new windows on the focused output.
            Niri.focusMonitor(root.screenName);
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
            Niri.focusWindow(row.windowId);
            root.close();
        } else if (row.kind === "calc") {
            Quickshell.execDetached(["wl-copy", "--", row.value]);
            root.close();
        } else if (row.kind === "clip") {
            Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", row.clipId]);
            root.close();
        } else if (row.kind === "power") {
            root.runPower(row.action);
        }
    }

    // Log out, Reboot and Power off need a second Enter (or click) within 3 s.
    function runPower(key) {
        const p = root.powerActions.find((a) => a.key === key);
        if (!p)
            return;
        if (p.confirm && root.armed !== key) {
            root.armed = key;
            disarm.restart();
            return;
        }
        root.close();
        const color = Theme.card.toString().slice(1, 7);
        const lock = Programs.has("swaylock")
            ? ["swaylock", "-f", "-c", color] : ["loginctl", "lock-session"];
        if (key === "lock")
            Quickshell.execDetached(lock);
        else if (key === "suspend")
            Quickshell.execDetached(["sh", "-c", "\"$@\" && systemctl suspend", "sh"].concat(lock));
        else if (key === "logout")
            Niri.quit();
        else if (key === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (key === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }
}
