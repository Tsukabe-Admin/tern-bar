.pragma library

// The weather lookup's logic, for singletons/Weather.qml: the condition icons,
// the addresses it asks, and the readers that turn an Open-Meteo or a wttr.in
// reply into the one object the bar shows and caches:
//   { temp, feelsLike, tempC, feelsC, icon, desc,
//     forecast: [{ date, icon, max, min, maxC, minC, desc }] }   (at most 5 days)
// A reader throws on a reply it cannot use, and Weather.qml then tries the
// next source. This was a python3 helper (scripts/weather.sh) until it moved
// into the bar; its rounding is kept, so the numbers shown stay the same.

// wttr.in's condition codes (World Weather Online): [icon, description].
var WWO_ICONS = {
    "113": ["󰖙", "Clear"],
    "116": ["󰖕", "Partly cloudy"],
    "119": ["󰖐", "Cloudy"],
    "122": ["󰖐", "Overcast"],
    "143": ["󰖑", "Mist"],
    "176": ["󰼳", "Patchy rain"],
    "179": ["󰼴", "Patchy snow"],
    "182": ["󰙿", "Sleet"],
    "185": ["󰙿", "Freezing drizzle"],
    "200": ["󰙾", "Thundery"],
    "227": ["󰖘", "Blowing snow"],
    "230": ["󰼶", "Blizzard"],
    "248": ["󰖑", "Fog"],
    "260": ["󰖑", "Freezing fog"],
    "263": ["󰼳", "Light drizzle"],
    "266": ["󰼳", "Drizzle"],
    "281": ["󰙿", "Freezing drizzle"],
    "284": ["󰙿", "Heavy freezing drizzle"],
    "293": ["󰼳", "Light rain"],
    "296": ["󰖗", "Light rain"],
    "299": ["󰖗", "Moderate rain"],
    "302": ["󰖗", "Rain"],
    "305": ["󰖖", "Heavy rain"],
    "308": ["󰖖", "Heavy rain"],
    "311": ["󰙿", "Freezing rain"],
    "314": ["󰙿", "Heavy freezing rain"],
    "317": ["󰙿", "Sleet"],
    "320": ["󰙿", "Heavy sleet"],
    "323": ["󰼴", "Light snow"],
    "326": ["󰼴", "Light snow"],
    "329": ["󰖘", "Moderate snow"],
    "332": ["󰖘", "Snow"],
    "335": ["󰼶", "Heavy snow"],
    "338": ["󰼶", "Heavy snow"],
    "350": ["󰙿", "Ice pellets"],
    "353": ["󰼳", "Light shower"],
    "356": ["󰖖", "Heavy shower"],
    "359": ["󰖖", "Torrential rain"],
    "362": ["󰙿", "Sleet showers"],
    "365": ["󰙿", "Heavy sleet showers"],
    "368": ["󰼴", "Snow showers"],
    "371": ["󰼶", "Heavy snow showers"],
    "374": ["󰙿", "Ice pellet showers"],
    "377": ["󰙿", "Heavy ice pellets"],
    "386": ["󰙾", "Thunderstorm"],
    "389": ["󰙾", "Heavy thunderstorm"],
    "392": ["󰙾", "Thundery snow"],
    "395": ["󰙾", "Heavy thundery snow"]
};

// Open-Meteo's condition codes (WMO): [icon, description].
var WMO_ICONS = {
    "0": ["󰖙", "Clear sky"],
    "1": ["󰖙", "Mainly clear"],
    "2": ["󰖕", "Partly cloudy"],
    "3": ["󰖐", "Overcast"],
    "45": ["󰖑", "Fog"],
    "48": ["󰖑", "Rime fog"],
    "51": ["󰼳", "Light drizzle"],
    "53": ["󰼳", "Drizzle"],
    "55": ["󰼳", "Dense drizzle"],
    "56": ["󰙿", "Freezing drizzle"],
    "57": ["󰙿", "Freezing drizzle"],
    "61": ["󰖗", "Slight rain"],
    "63": ["󰖗", "Rain"],
    "65": ["󰖖", "Heavy rain"],
    "66": ["󰙿", "Freezing rain"],
    "67": ["󰙿", "Heavy freezing rain"],
    "71": ["󰼴", "Slight snow"],
    "73": ["󰖘", "Snow"],
    "75": ["󰼶", "Heavy snow"],
    "77": ["󰖘", "Snow grains"],
    "80": ["󰼳", "Rain showers"],
    "81": ["󰖗", "Rain showers"],
    "82": ["󰖖", "Violent showers"],
    "85": ["󰼴", "Snow showers"],
    "86": ["󰼶", "Heavy snow showers"],
    "95": ["󰙾", "Thunderstorm"],
    "96": ["󰙾", "Thunderstorm with hail"],
    "99": ["󰙾", "Thunderstorm with hail"]
};

// A condition the table does not know: the "partly cloudy" icon.
var UNKNOWN = ["󰖕", "Clear"];

var GEO_URL = "https://ipwho.is/";
var GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search";
var METEO_URL = "https://api.open-meteo.com/v1/forecast";
var WTTR_BASE = "https://wttr.in";

// Every environment variable the lookup reads; Weather.qml passes their values in.
var ENV_NAMES = ["SKUA_WEATHER_MOCK", "SKUA_WEATHER_COORDS", "SKUA_WEATHER_LOCATION",
    "SKUA_WEATHER_GEO_URL", "SKUA_WEATHER_GEOCODE_URL", "SKUA_WEATHER_METEO_URL",
    "SKUA_WEATHER_WTTR_BASE"];

// A variable's text, trimmed; "" when unset (Quickshell.env gives null then).
function env(vars, name) {
    const value = vars ? vars[name] : null;
    return value === undefined || value === null ? "" : String(value).trim();
}

function lookup(table, code, fallback) {
    const key = String(code);
    return Object.prototype.hasOwnProperty.call(table, key) ? table[key] : fallback;
}

// A JSON object as it is; anything else (null, a list, text) as an empty one.
function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function list(value) {
    return Array.isArray(value) ? value : [];
}

// A number, from a number or from text such as wttr.in's "15"; throws otherwise.
function num(value) {
    const n = (typeof value === "number" || (typeof value === "string" && value.trim() !== ""))
        ? Number(value) : NaN;
    if (!isFinite(n))
        throw new Error("not a number: " + value);
    return n;
}

// The nearest whole number, a tie going to the even one (2.5 -> 2, -0.5 -> 0)
// as Python's round() did in the old helper. Math.round would show 3°.
function round(x) {
    const below = Math.floor(x);
    const rest = x - below;
    const n = (rest > 0.5 || (rest === 0.5 && below % 2 !== 0)) ? below + 1 : below;
    return n === 0 ? 0 : n;    // never -0
}

// A temperature as a whole number. A missing one is `fallback`; without a
// fallback it is an error.
function temp(value, fallback) {
    return fallback !== undefined && (value === undefined || value === null) ? fallback : round(num(value));
}

// SKUA_WEATHER_MOCK: its JSON is used as the result. Text that does not parse,
// or parses to null, means there is no mock.
function mock(vars) {
    const text = env(vars, "SKUA_WEATHER_MOCK");
    try {
        return text === "" ? null : JSON.parse(text);
    } catch (e) {
        return null;
    }
}

// SKUA_WEATHER_COORDS "lat,lon" as [lat, lon]; null when it holds no comma.
// A part that is not a number throws, so neither source falls back to the
// place name or the IP address: the coordinates were what was meant.
function coords(vars) {
    const text = env(vars, "SKUA_WEATHER_COORDS");
    const comma = text.indexOf(",");
    return comma === -1 ? null : [num(text.slice(0, comma)), num(text.slice(comma + 1))];
}

// Where the Open-Meteo lookup gets its coordinates: { coords: [lat, lon] }
// from SKUA_WEATHER_COORDS, or { url, read } for a request whose reply `read`
// turns into [lat, lon]: the geocoder for SKUA_WEATHER_LOCATION, else the IP
// address's place. Throws on coordinates that are not numbers.
function locate(vars) {
    const c = coords(vars);
    if (c)
        return { coords: c };
    const place = env(vars, "SKUA_WEATHER_LOCATION");
    if (place !== "")
        return { url: (env(vars, "SKUA_WEATHER_GEOCODE_URL") || GEOCODE_URL) + "?name="
            + encodeURIComponent(place) + "&count=1&format=json", read: fromGeocode };
    return { url: env(vars, "SKUA_WEATHER_GEO_URL") || GEO_URL, read: latLon };
}

// A coordinate always with a decimal point, as the old helper wrote it:
// wttr.in reads "52,13" as a place name (it answered for a town in France on
// 2026-11-16) and only "52.0,13.0" as GPS coordinates.
function coordText(n) {
    return Number.isInteger(n) ? n.toFixed(1) : String(n);
}

function meteoUrl(vars, lat, lon) {
    return (env(vars, "SKUA_WEATHER_METEO_URL") || METEO_URL) + "?latitude=" + coordText(lat)
        + "&longitude=" + coordText(lon)
        + "&current=temperature_2m,apparent_temperature,weather_code"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&timezone=auto&forecast_days=5";
}

// The same order as locate(): coordinates, then a place name. With neither,
// the path is empty and wttr.in works the place out from the request's IP
// address, so coordinates must never be dropped here.
function wttrUrl(vars) {
    const c = coords(vars);
    const target = c ? coordText(c[0]) + "," + coordText(c[1])    // wttr.in reads "lat,lon" as GPS coordinates
        : encodeURIComponent(env(vars, "SKUA_WEATHER_LOCATION"));
    const base = (env(vars, "SKUA_WEATHER_WTTR_BASE") || WTTR_BASE).replace(/\/+$/, "");
    return base + "/" + target + "?format=j1";
}

// [lat, lon] of a place (the IP lookup's whole reply is one); throws when
// either is missing.
function latLon(place) {
    return [num(object(place).latitude), num(object(place).longitude)];
}

// The geocoder's first result; it sends no `results` for a place it does not know.
function fromGeocode(reply) {
    return latLon(list(object(reply).results)[0]);
}

function result(tempC, feelsC, look, desc, forecast) {
    return { temp: tempC + "°C", feelsLike: feelsC + "°C", tempC: tempC, feelsC: feelsC,
        icon: look[0], desc: desc, forecast: forecast };
}

function day(date, look, maxC, minC, desc) {
    return { date: String(date), icon: look[0], max: maxC + "°", min: minC + "°", maxC: maxC, minC: minC, desc: desc };
}

// An Open-Meteo forecast reply (the address from meteoUrl). No default for the
// current temperature, in either reader: a reply without one is not weather,
// and a made-up 0° would be shown, and cached, as if it were.
function fromOpenMeteo(reply) {
    const cur = object(object(reply).current);
    const now = lookup(WMO_ICONS, cur.weather_code === undefined ? 0 : cur.weather_code, UNKNOWN);
    const tempC = temp(cur.temperature_2m);
    const feelsC = temp(cur.apparent_temperature, tempC);
    const daily = object(object(reply).daily);
    const codes = list(daily.weather_code);
    const maxs = list(daily.temperature_2m_max);
    const mins = list(daily.temperature_2m_min);
    // A day without a code, or with one the table does not know, takes the
    // current condition.
    const forecast = list(daily.time).slice(0, 5).map((date, i) => {
        const look = lookup(WMO_ICONS, codes[i], now);
        return day(date, look, temp(maxs[i], tempC), temp(mins[i], tempC), look[1]);
    });
    return result(tempC, feelsC, now, now[1], forecast);
}

// wttr.in's words for a condition, weatherDesc[0].value, trimmed ("Cloudy ").
function descOf(condition) {
    const value = object(list(condition.weatherDesc)[0]).value;
    return typeof value === "string" ? value.trim() : "";
}

// A wttr.in reply (the address from wttrUrl, format=j1).
function fromWttr(reply) {
    const cur = object(list(object(reply).current_condition)[0]);
    const now = lookup(WWO_ICONS, cur.weatherCode === undefined ? "113" : cur.weatherCode, UNKNOWN);
    const tempC = temp(cur.temp_C);
    const feelsC = temp(cur.FeelsLikeC, tempC);
    const forecast = list(object(reply).weather).slice(0, 5).map((entry) => {
        const w = object(entry);
        const hours = list(w.hourly);
        // The condition at midday stands for the day. A day without hours, or
        // with a code the table does not know, takes the current icon.
        const mid = object(hours[Math.floor(hours.length / 2)]);
        const look = lookup(WWO_ICONS, mid.weatherCode, now);
        return day(w.date === undefined ? "" : w.date, look, temp(w.maxtempC, tempC), temp(w.mintempC, tempC),
            descOf(mid) || look[1]);
    });
    return result(tempC, feelsC, now, descOf(cur) || now[1], forecast);
}
