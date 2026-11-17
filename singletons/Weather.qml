pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "weather.js" as WeatherLib

// Shared weather state for the bar's weather pill and the forecast inside
// CalendarPopup. Polled once every 30 minutes while either the weather or clock
// pill is shown on the bar, and seeded immediately from the cached state file
// ($XDG_STATE_HOME/skua/weather.json) so restarts never blank the pill. The
// lookup needs no API key: Open-Meteo, with wttr.in as the fallback, asked
// with XMLHttpRequest. weather.js builds the addresses and reads the replies.
Singleton {
    id: root

    property bool available: false
    property real tempC: 0
    property real feelsC: 0
    property string icon: "󰖕"
    property string desc: ""
    property var forecast: []

    // Displayed values follow BarConfig.weatherFahrenheit; the stored numbers
    // stay Celsius, so switching units never needs a new fetch.
    readonly property string temp: root.available ? root.formatTemp(root.tempC) : ""
    readonly property string feelsLike: root.available ? root.formatTemp(root.feelsC) : ""

    readonly property bool wanted: BarConfig.configLoaded
        && (BarConfig.hidden.indexOf("weather") === -1 || BarConfig.hidden.indexOf("clock") === -1)

    // A lookup is on its way; a refresh asked for meanwhile sets `recheck`, and
    // one more lookup runs when this one is over.
    property bool busy: false
    property bool recheck: false
    // The request on its way, { xhr, failed }, and its number. Anything a
    // request sends once it is no longer the current one is ignored.
    property var request: null
    property int ticket: 0
    // Set at Component.onCompleted. `wanted` can turn true earlier, while this
    // object is still being built (bar.json is read then), when the cache has
    // not been read and cacheFile cannot write yet; the first lookup waits.
    property bool started: false

    function toCelsius(value) {
        const n = parseFloat(String(value));
        return isFinite(n) ? n : 0;
    }

    // `showUnit` is false for the forecast columns, where the header already
    // shows whether the numbers are °C or °F.
    function formatTemp(celsius, showUnit) {
        const n = Number(celsius);
        if (!isFinite(n))
            return "";
        const value = BarConfig.weatherFahrenheit ? Math.round(n * 9 / 5 + 32) : Math.round(n);
        if (showUnit === false)
            return value + "°";
        return value + (BarConfig.weatherFahrenheit ? "°F" : "°C");
    }

    // The forecast from `now`'s day on, at most five days. A forecast kept past
    // midnight, or read back from the cache the next day, still begins with the
    // day it was fetched on; that day is not shown.
    function daysFrom(now) {
        const today = Qt.formatDate(now, "yyyy-MM-dd");
        return root.forecast.filter((d) => String(d.date || "") >= today).slice(0, 5);
    }

    // The heading of a forecast column: "Today", or the weekday of `isoDate`
    // ("2026-11-10"), seen from `now`. It is worked out when the column is shown
    // and not when the forecast was fetched, so it cannot be a day out.
    function dayLabel(isoDate, now) {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(isoDate || ""));
        if (!m)
            return "";
        if (m[0] === Qt.formatDate(now, "yyyy-MM-dd"))
            return "Today";
        const day = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day.getDay()];
    }

    function applyJson(line) {
        try {
            const o = JSON.parse(line);
            if (!o || typeof o !== "object")
                return;
            // New files carry numbers; old caches only the formatted strings.
            const rawTemp = (o.tempC !== undefined && o.tempC !== null && o.tempC !== "")
                ? o.tempC : o.temp;
            if (rawTemp === undefined || rawTemp === null || rawTemp === "")
                return;
            root.tempC = root.toCelsius(rawTemp);
            const rawFeels = (o.feelsC !== undefined && o.feelsC !== null && o.feelsC !== "")
                ? o.feelsC : o.feelsLike;
            root.feelsC = root.toCelsius(rawFeels !== undefined ? rawFeels : root.tempC);
            root.icon = String(o.icon || "󰖕");
            root.desc = String(o.desc || "");
            const days = Array.isArray(o.forecast) ? o.forecast : [];
            root.forecast = days.map((d) => {
                const copy = Object.assign({}, d);
                copy.maxC = root.toCelsius(d.maxC !== undefined ? d.maxC : d.max);
                copy.minC = root.toCelsius(d.minC !== undefined ? d.minC : d.min);
                return copy;
            });
            root.available = true;
        } catch (e) {
        }
    }

    function refresh() {
        if (root.busy)
            root.recheck = true;
        else
            root.lookUp();
    }

    // One lookup, in the order the bar has always used: SKUA_WEATHER_MOCK, then
    // Open-Meteo, then wttr.in. A step that fails (no answer in time, an error
    // status, a reply that is not weather) moves on to the next source; when
    // both fail, the last good weather stays on screen.
    function lookUp() {
        root.busy = true;
        const vars = {};
        for (const name of WeatherLib.ENV_NAMES)
            vars[name] = Quickshell.env(name);
        const mock = WeatherLib.mock(vars);
        if (mock !== null) {
            root.succeed(mock);
            return;
        }
        root.fromOpenMeteo(vars, () => root.fromWttr(vars, () => root.finish(false)));
    }

    // The coordinates (given, looked up from the place name, or the IP
    // address's place), then the forecast there.
    function fromOpenMeteo(vars, failed) {
        const forecastAt = (latLon) => root.fetchJson(WeatherLib.meteoUrl(vars, latLon[0], latLon[1]), 5000,
            WeatherLib.fromOpenMeteo, root.succeed, failed);
        let where;
        try {
            where = WeatherLib.locate(vars);
        } catch (e) {
            failed();
            return;
        }
        if (where.coords)
            forecastAt(where.coords);
        else
            root.fetchJson(where.url, 4000, where.read, forecastAt, failed);
    }

    function fromWttr(vars, failed) {
        let url;
        try {
            url = WeatherLib.wttrUrl(vars);
        } catch (e) {
            failed();
            return;
        }
        root.fetchJson(url, 5000, WeatherLib.fromWttr, root.succeed, failed);
    }

    // GET `url`; `read` turns its JSON into what `next` is given. No answer
    // within `ms`, a status other than 2xx, a body that is not JSON, or one
    // `read` throws on: `failed` is called instead. One request at a time.
    function fetchJson(url, ms, read, next, failed) {
        const ticket = ++root.ticket;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || ticket !== root.ticket)
                return;
            root.settle();
            let value;
            try {
                if (xhr.status < 200 || xhr.status >= 300)
                    throw new Error("HTTP " + xhr.status);
                value = read(JSON.parse(xhr.responseText));
            } catch (e) {
                failed();
                return;
            }
            next(value);
        };
        root.request = { xhr: xhr, failed: failed };
        requestTimer.interval = ms;
        requestTimer.restart();
        try {
            xhr.open("GET", url);
            // Qt passes this header on (checked with a local server, Qt 6.12),
            // although browsers drop it: the old python3 helper sent the same.
            xhr.setRequestHeader("User-Agent", "skua/1.0");
            xhr.send();
        } catch (e) {
            if (ticket === root.ticket) {
                root.settle();
                failed();
            }
        }
    }

    // The current request is over: whatever it still sends is ignored.
    function settle() {
        root.ticket++;
        root.request = null;
        requestTimer.stop();
    }

    // A lookup's result (or the mock): shown, and kept for the next start.
    function succeed(result) {
        const json = JSON.stringify(result);
        root.applyJson(json);
        cacheFile.setText(json);
        root.finish(true);
    }

    function finish(ok) {
        root.busy = false;
        if (root.recheck) {
            root.recheck = false;
            root.lookUp();
        } else if (!ok && root.wanted) {
            retryTimer.restart();
        }
    }

    FileView {
        id: cacheFile
        path: BarConfig.stateDir + "/weather.json"
        blockLoading: true
        printErrors: false
        // Written to a temporary file and moved into place, so a crash halfway
        // through never leaves half a file for the next start to read.
        atomicWrites: true
    }

    // XMLHttpRequest has no timeout of its own.
    Timer {
        id: requestTimer
        onTriggered: {
            const request = root.request;
            root.settle();
            if (request) {
                request.xhr.abort();
                request.failed();
            }
        }
    }

    Timer {
        interval: 1800000
        repeat: true
        running: root.wanted
        onTriggered: root.refresh()
    }

    Timer {
        id: retryTimer
        interval: 60000
        onTriggered: {
            if (root.wanted)
                root.refresh();
        }
    }

    onWantedChanged: {
        if (root.wanted && root.started)
            root.refresh();
    }

    Component.onCompleted: {
        root.applyJson(cacheFile.text());
        root.started = true;
        if (root.wanted)
            root.refresh();
    }

    // A reload builds a new Weather. A request of the old one must not answer
    // later and write its weather over the new one's cache.
    Component.onDestruction: {
        root.ticket++;
        if (root.request)
            root.request.xhr.abort();
    }
}
