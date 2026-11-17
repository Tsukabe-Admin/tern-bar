// The weather lookup's logic (singletons/weather.js). Run with: node --test tests/
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// weather.js is a QML script library: a ".pragma library" line and plain
// functions, no exports. Drop that line and it is ordinary JavaScript.
const source = readFileSync(new URL("../singletons/weather.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const W = new Function(`${source}
return { fromOpenMeteo, fromWttr, locate, meteoUrl, wttrUrl, mock, round };`)();

// The icons, as code points: a glyph damaged in weather.js shows up here.
const PARTLY = "\u{F0595}";
const CLOUDY = "\u{F0590}";
const RAIN = "\u{F0597}";
const SHOWER = "\u{F0F33}";
const FOG = "\u{F0591}";

const clone = (o) => JSON.parse(JSON.stringify(o));

// Open-Meteo's reply for Berlin, recorded 2026-11-16 (unused fields dropped).
const METEO = {
    latitude: 52.512604, longitude: 13.419517, timezone: "Europe/Berlin",
    current: { time: "2026-11-17T06:00", interval: 900, temperature_2m: 5.7, apparent_temperature: 2.8, weather_code: 3 },
    daily: {
        time: ["2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21"],
        weather_code: [63, 80, 61, 61, 80],
        temperature_2m_max: [8.1, 11.2, 9.9, 6.2, 6.7],
        temperature_2m_min: [4.8, 8.1, 6.2, 2.7, 3.0]
    }
};

// wttr.in's format=j1 reply for Paris, recorded 2026-11-16: the fields the bar
// reads, with the eight three-hourly conditions of each day as they came.
function hours(list) {
    return list.map(([code, desc], i) => ({ time: String(i * 300), weatherCode: code, weatherDesc: [{ value: desc }] }));
}
const WTTR = {
    current_condition: [{ temp_C: "15", FeelsLikeC: "15", weatherCode: "302", weatherDesc: [{ value: "Moderate rain" }] }],
    weather: [
        { date: "2026-11-17", maxtempC: "16", mintempC: "11", hourly: hours([["266", "Light drizzle"], ["296", "Light rain"],
            ["353", "Light rain shower"], ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"],
            ["176", "Patchy rain nearby"], ["353", "Light rain shower"], ["353", "Light rain shower"]]) },
        { date: "2026-11-18", maxtempC: "14", mintempC: "11", hourly: hours([["176", "Patchy rain nearby"],
            ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"],
            ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"], ["119", "Cloudy "]]) },
        { date: "2026-11-19", maxtempC: "12", mintempC: "9", hourly: hours([["353", "Light rain shower"], ["296", "Light rain"],
            ["353", "Light rain shower"], ["119", "Cloudy "], ["176", "Patchy rain nearby"], ["176", "Patchy rain nearby"],
            ["176", "Patchy rain nearby"], ["122", "Overcast "]]) }
    ]
};

test("an Open-Meteo reply becomes the object the bar shows and caches", () => {
    assert.deepEqual(W.fromOpenMeteo(METEO), {
        temp: "6°C", feelsLike: "3°C", tempC: 6, feelsC: 3, icon: CLOUDY, desc: "Overcast",
        forecast: [
            { date: "2026-11-17", icon: RAIN, max: "8°", min: "5°", maxC: 8, minC: 5, desc: "Rain" },
            { date: "2026-11-18", icon: SHOWER, max: "11°", min: "8°", maxC: 11, minC: 8, desc: "Rain showers" },
            { date: "2026-11-19", icon: RAIN, max: "10°", min: "6°", maxC: 10, minC: 6, desc: "Slight rain" },
            { date: "2026-11-20", icon: RAIN, max: "6°", min: "3°", maxC: 6, minC: 3, desc: "Slight rain" },
            { date: "2026-11-21", icon: SHOWER, max: "7°", min: "3°", maxC: 7, minC: 3, desc: "Rain showers" }
        ]
    });
});

test("a wttr.in reply gives the same shape, each day shown by its midday condition", () => {
    assert.deepEqual(W.fromWttr(WTTR), {
        temp: "15°C", feelsLike: "15°C", tempC: 15, feelsC: 15, icon: RAIN, desc: "Moderate rain",
        forecast: [
            { date: "2026-11-17", icon: SHOWER, max: "16°", min: "11°", maxC: 16, minC: 11, desc: "Patchy rain nearby" },
            { date: "2026-11-18", icon: SHOWER, max: "14°", min: "11°", maxC: 14, minC: 11, desc: "Patchy rain nearby" },
            { date: "2026-11-19", icon: SHOWER, max: "12°", min: "9°", maxC: 12, minC: 9, desc: "Patchy rain nearby" }
        ]
    });
});

test("wttr.in's descriptions lose the spaces around them", () => {
    const reply = clone(WTTR);
    reply.current_condition[0].weatherDesc = [{ value: "  Sunny " }];
    reply.weather[0].hourly[4].weatherDesc = [{ value: "Cloudy " }];
    const got = W.fromWttr(reply);
    assert.equal(got.desc, "Sunny");
    assert.equal(got.forecast[0].desc, "Cloudy");
});

test("a reply without the current temperature is an error, never a made-up 0°", () => {
    const meteo = clone(METEO);
    delete meteo.current.temperature_2m;
    assert.throws(() => W.fromOpenMeteo(meteo));
    meteo.current.temperature_2m = null;
    assert.throws(() => W.fromOpenMeteo(meteo));
    assert.throws(() => W.fromOpenMeteo({ daily: METEO.daily }));

    const wttr = clone(WTTR);
    delete wttr.current_condition[0].temp_C;
    assert.throws(() => W.fromWttr(wttr));
    assert.throws(() => W.fromWttr({ weather: WTTR.weather }));
});

test("the forecast has at most five days", () => {
    const meteo = clone(METEO);
    meteo.daily.time.push("2026-11-22", "2026-11-23");
    meteo.daily.weather_code.push(0, 0);
    assert.deepEqual(W.fromOpenMeteo(meteo).forecast.map((d) => d.date),
        ["2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21"]);

    const wttr = clone(WTTR);
    for (let i = 20; i < 24; i++)
        wttr.weather.push(Object.assign(clone(WTTR.weather[0]), { date: "2026-11-" + i }));
    assert.equal(W.fromWttr(wttr).forecast.length, 5);
});

test("a condition code the tables do not know falls back as before", () => {
    // A day: the current condition (here 3, "Overcast"). Now: the partly-cloudy
    // icon and "Clear".
    const meteo = clone(METEO);
    meteo.daily.weather_code = [45, 1234];      // also shorter than the days
    assert.deepEqual(W.fromOpenMeteo(meteo).forecast.map((d) => [d.icon, d.desc]),
        [[FOG, "Fog"], [CLOUDY, "Overcast"], [CLOUDY, "Overcast"], [CLOUDY, "Overcast"], [CLOUDY, "Overcast"]]);
    meteo.current.weather_code = 4;
    const om = W.fromOpenMeteo(meteo);
    assert.deepEqual([om.icon, om.desc], [PARTLY, "Clear"]);
    assert.deepEqual([om.forecast[1].icon, om.forecast[1].desc], [PARTLY, "Clear"]);

    // wttr.in: an unknown code keeps the reply's own words; without words the
    // day takes the current icon and the table's word for the current code.
    const wttr = clone(WTTR);
    wttr.current_condition[0].weatherCode = "999";
    wttr.weather[0].hourly[4] = { weatherCode: "998" };
    const wt = W.fromWttr(wttr);
    assert.deepEqual([wt.icon, wt.desc], [PARTLY, "Moderate rain"]);
    assert.deepEqual([wt.forecast[0].icon, wt.forecast[0].desc], [PARTLY, "Clear"]);

    const known = clone(WTTR);                   // now: 302, "Rain"
    known.weather[1].hourly = [];                // no hours: the current condition
    known.weather[2].hourly[4] = { weatherCode: "998" };
    const days = W.fromWttr(known).forecast;
    assert.deepEqual([days[1].icon, days[1].desc], [RAIN, "Rain"]);
    assert.deepEqual([days[2].icon, days[2].desc], [RAIN, "Rain"]);
});

test("halves round to the even number, as the old python3 helper did", () => {
    assert.deepEqual([0.5, 1.5, 2.5, 3.5, -0.5, -1.5, -2.5, 2.6, -2.6].map(W.round), [0, 2, 2, 4, 0, -2, -2, 3, -3]);

    const meteo = clone(METEO);
    meteo.current.temperature_2m = 2.5;
    meteo.current.apparent_temperature = -0.5;
    meteo.daily.temperature_2m_max[0] = 3.5;
    const got = W.fromOpenMeteo(meteo);
    assert.deepEqual([got.temp, got.feelsLike, got.forecast[0].max], ["2°C", "0°C", "4°"]);
});

const TAIL = "&current=temperature_2m,apparent_temperature,weather_code"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5";

// wttr.in reads "52,13" as a place name and answers for somewhere else
// entirely; "52.0,13.0" is read as coordinates.
test("coordinates go into both addresses, whole numbers with a decimal point", () => {
    const at = (coords) => {
        const vars = { SKUA_WEATHER_COORDS: coords };
        const where = W.locate(vars);
        return [W.meteoUrl(vars, where.coords[0], where.coords[1]), W.wttrUrl(vars)];
    };
    assert.deepEqual(at("52,13"), ["https://api.open-meteo.com/v1/forecast?latitude=52.0&longitude=13.0" + TAIL,
        "https://wttr.in/52.0,13.0?format=j1"]);
    assert.deepEqual(at(" 52.520 , 13.405 "), ["https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.405" + TAIL,
        "https://wttr.in/52.52,13.405?format=j1"]);
    assert.equal(at("-23,-46.5")[1], "https://wttr.in/-23.0,-46.5?format=j1");
});

test("coordinates that are not numbers fail, and never fall back to the place name", () => {
    const vars = { SKUA_WEATHER_COORDS: "52.5,east", SKUA_WEATHER_LOCATION: "Berlin" };
    assert.throws(() => W.locate(vars));
    assert.throws(() => W.wttrUrl(vars));
});

test("a place name is looked up, encoded for the address", () => {
    const where = W.locate({ SKUA_WEATHER_LOCATION: " São Paulo " });
    assert.equal(where.url, "https://geocoding-api.open-meteo.com/v1/search?name=S%C3%A3o%20Paulo&count=1&format=json");
    assert.equal(W.wttrUrl({ SKUA_WEATHER_LOCATION: "Saint-Denis & Co?" }), "https://wttr.in/Saint-Denis%20%26%20Co%3F?format=j1");
    // Without a comma there are no coordinates: the place name is used.
    assert.equal(W.wttrUrl({ SKUA_WEATHER_COORDS: "52.5", SKUA_WEATHER_LOCATION: "Rome" }), "https://wttr.in/Rome?format=j1");
});

test("unset variables (null from Quickshell.env) give the default services", () => {
    const vars = { SKUA_WEATHER_COORDS: null, SKUA_WEATHER_LOCATION: null, SKUA_WEATHER_GEO_URL: null,
        SKUA_WEATHER_METEO_URL: null, SKUA_WEATHER_WTTR_BASE: null };
    assert.equal(W.locate(vars).url, "https://ipwho.is/");
    assert.equal(W.wttrUrl(vars), "https://wttr.in/?format=j1");
    assert.equal(W.meteoUrl(vars, 48.8566, 2.3522),
        "https://api.open-meteo.com/v1/forecast?latitude=48.8566&longitude=2.3522" + TAIL);
});

test("the server overrides are used, a base address without its trailing slashes", () => {
    const vars = { SKUA_WEATHER_LOCATION: "Oslo", SKUA_WEATHER_GEOCODE_URL: "http://127.0.0.1:8000/geo",
        SKUA_WEATHER_METEO_URL: "http://127.0.0.1:8000/m", SKUA_WEATHER_WTTR_BASE: "http://127.0.0.1:8000/w//" };
    assert.equal(W.locate(vars).url, "http://127.0.0.1:8000/geo?name=Oslo&count=1&format=json");
    assert.equal(W.meteoUrl(vars, 59.91, 10.75), "http://127.0.0.1:8000/m?latitude=59.91&longitude=10.75" + TAIL);
    assert.equal(W.wttrUrl(vars), "http://127.0.0.1:8000/w/Oslo?format=j1");
    assert.equal(W.locate({ SKUA_WEATHER_GEO_URL: "http://127.0.0.1:8000/ip" }).url, "http://127.0.0.1:8000/ip");
});

test("the geocoder's first result and the IP lookup give [lat, lon]; nothing found is an error", () => {
    const geocode = { results: [{ id: 3448439, name: "São Paulo", latitude: -23.5475, longitude: -46.63611, country_code: "BR" }],
        generationtime_ms: 0.138 };
    const byName = W.locate({ SKUA_WEATHER_LOCATION: "x" }).read;
    assert.deepEqual(byName(geocode), [-23.5475, -46.63611]);
    assert.throws(() => byName({ generationtime_ms: 0.1 }));     // the geocoder's answer for an unknown place
    const byIp = W.locate({}).read;
    assert.deepEqual(byIp({ ip: "203.0.113.7", success: true, latitude: 48.8566, longitude: 2.3522 }), [48.8566, 2.3522]);
    assert.throws(() => byIp({ success: false, message: "Reserved range" }));
});

test("SKUA_WEATHER_MOCK is used as the result only when it holds JSON", () => {
    assert.deepEqual(W.mock({ SKUA_WEATHER_MOCK: ' {"temp": "7°C", "tempC": 7} ' }), { temp: "7°C", tempC: 7 });
    assert.equal(W.mock({ SKUA_WEATHER_MOCK: "{not json" }), null);
    assert.equal(W.mock({ SKUA_WEATHER_MOCK: "null" }), null);
    assert.equal(W.mock({ SKUA_WEATHER_MOCK: null }), null);
});
