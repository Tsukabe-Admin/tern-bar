pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The bar is the desktop's notification daemon: it owns
// org.freedesktop.Notifications on the session bus, shows new notifications as
// toasts in the top-right corner (NotificationToasts) and keeps them in a
// history (NotificationCenter, the bell). While another daemon (swaync, mako,
// dunst) holds the name, Quickshell logs two warnings and takes the name over
// when that daemon exits.
//
// Do Not Disturb (saved in bar.json) keeps everything but critical
// notifications off the screen; they still go into the history.
Singleton {
    id: root

    readonly property bool dnd: BarConfig.doNotDisturb

    function toggleDnd() {
        BarConfig.setDoNotDisturb(!BarConfig.doNotDisturb);
    }

    // Newest first. Transient notifications (volume changes and the like) are
    // only toasts, never history.
    readonly property var history: server.trackedNotifications.values.filter((n) => !n.transient).reverse()
    readonly property int count: root.history.length

    // The notifications shown as toasts, newest first, at most three. A
    // notification leaves this list the moment it closes (see onClosed below).
    property var toasts: []

    // Arrival times by notification id; kept across hot reloads with the
    // notifications themselves. Kept as text: a JavaScript object cannot move
    // from the old QML engine to the new one.
    PersistentProperties {
        id: times
        reloadableId: "notificationTimes"
        property string json: "{}"
    }
    readonly property var arrivedAt: {
        try {
            return JSON.parse(times.json);
        } catch (e) {
            return {};
        }
    }

    // "now", "5 min", "2 h", or the time of day after a day.
    property double now: Date.now()

    function timeOf(n) {
        const t = root.arrivedAt[n.id];
        if (!t)
            return "";
        const s = (root.now - t) / 1000;
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + " min";
        if (s < 86400)
            return Math.floor(s / 3600) + " h";
        return Qt.formatDateTime(new Date(t), "HH:mm");
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.count > 0
        onTriggered: root.now = Date.now()
    }

    function arrived(n) {
        n.tracked = true;
        const at = {};
        for (const t of server.trackedNotifications.values) {
            if (root.arrivedAt[t.id])
                at[t.id] = root.arrivedAt[t.id];
        }
        at[n.id] = Date.now();
        times.json = JSON.stringify(at);
        root.now = Date.now();
        // Keep 50: the oldest go first. The new one joins the list only after
        // this handler, so 49 of the others stay.
        const all = server.trackedNotifications.values;
        for (let i = 0; i < all.length - 49; i++)
            all[i].expire();
        root.show(n);
    }

    // As a toast, unless Do Not Disturb is on and it is not critical. An app
    // that replaces its notification (a new track, a download's progress) gets
    // its toast back too.
    function show(n) {
        if (!n || !n.tracked || (root.dnd && n.urgency !== NotificationUrgency.Critical))
            return;
        root.toasts = [n].concat(root.toasts.filter((t) => t !== n)).slice(0, 3);
    }

    // How long a toast stays: what the app asked for (milliseconds), else 3 s
    // for low urgency and 6 s for normal; critical ones stay until dismissed.
    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        if (n.expireTimeout > 0)
            return n.expireTimeout;
        return n.urgency === NotificationUrgency.Low ? 3000 : 6000;
    }

    // The toast goes; the notification stays in the history (a transient one
    // is gone for good).
    function hideToast(n) {
        root.toasts = root.toasts.filter((t) => t !== n);
        if (n && n.tracked && n.transient)
            n.expire();
    }

    function dismiss(n) {
        root.toasts = root.toasts.filter((t) => t !== n);
        if (n && n.tracked)
            n.dismiss();
    }

    function clear() {
        root.toasts = [];
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    // An action button. Unless the app marked it resident, the notification
    // closes with it.
    function invoke(n, action) {
        root.toasts = root.toasts.filter((t) => t !== n);
        action.invoke();
    }

    // A click on the notification itself: its "default" action when it has
    // one (usually: open the app there), else the toast just goes.
    function invokeDefault(n) {
        const action = n.actions.find((a) => a.identifier === "default");
        if (action)
            root.invoke(n, action);
        else
            root.hideToast(n);
    }

    // The buttons a card shows: every action except "default", at most three.
    function buttonsOf(n) {
        return n.actions.filter((a) => a.identifier !== "default" && a.text !== "").slice(0, 3);
    }

    // The picture for a card: the notification's own image, else its app's
    // icon. Only local pictures: a file, an icon of the theme, or the image
    // data the app sent. A web address gives no picture (the bar would fetch
    // it). Quickshell hands an image path over as "image://icon/<path>".
    function imageFor(n) {
        const pick = (value) => {
            let text = String(value || "");
            if (text.startsWith("image://icon/"))
                text = text.slice("image://icon/".length);
            if (text === "")
                return "";
            if (text.startsWith("/"))
                return "file://" + text;
            if (text.startsWith("file://") || text.startsWith("image://"))
                return text;
            if (text.indexOf("://") !== -1)
                return "";
            return Quickshell.iconPath(text, true);
        };
        const image = pick(n.image);
        return image !== "" ? image : pick(n.appIcon);
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        persistenceSupported: true
        inlineReplySupported: false
        onNotification: (n) => root.arrived(n)
    }

    // A replaced notification keeps its object and only changes its text.
    //
    // A closed one leaves the toasts at once. Quickshell never emits
    // trackedChanged, and a notification its app withdraws (CloseNotification)
    // keeps `tracked` true until it is deleted, so a filter on `tracked` never
    // updates: the toast stayed as an empty card over a deleted object, and a
    // click on it threw. `closed` comes for every way a notification ends,
    // before the object goes.
    Instantiator {
        model: server.trackedNotifications

        delegate: Connections {
            required property var modelData
            target: modelData

            function onSummaryChanged() {
                root.show(modelData);
            }

            function onBodyChanged() {
                root.show(modelData);
            }

            function onClosed() {
                if (root.toasts.includes(modelData))
                    root.toasts = root.toasts.filter((t) => t !== modelData);
            }
        }
    }
}
