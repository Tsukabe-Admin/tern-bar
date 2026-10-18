#!/usr/bin/env bash
# Weather helper for tern-bar: fetches current conditions and multi-day forecast
# without requiring an API key (wttr.in with Open-Meteo fallback) and caches the
# normalized JSON in $XDG_STATE_HOME/tern-bar/weather.json.

set -eu

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tern-bar"
CACHE_FILE="$STATE_DIR/weather.json"

if ! command -v python3 >/dev/null 2>&1; then
    exit 1
fi

mkdir -p "$STATE_DIR"

python3 - "$CACHE_FILE" <<'PY'
import datetime
import json
import os
import sys
import urllib.parse
import urllib.request

cache_path = sys.argv[1]

WWO_ICONS = {
    "113": ("󰖙", "Clear"),
    "116": ("󰖕", "Partly cloudy"),
    "119": ("󰖐", "Cloudy"),
    "122": ("󰖐", "Overcast"),
    "143": ("󰖑", "Mist"),
    "176": ("󰼳", "Patchy rain"),
    "179": ("󰼴", "Patchy snow"),
    "182": ("󰙿", "Sleet"),
    "185": ("󰙿", "Freezing drizzle"),
    "200": ("󰙾", "Thundery"),
    "227": ("󰖘", "Blowing snow"),
    "230": ("󰼶", "Blizzard"),
    "248": ("󰖑", "Fog"),
    "260": ("󰖑", "Freezing fog"),
    "263": ("󰼳", "Light drizzle"),
    "266": ("󰼳", "Drizzle"),
    "281": ("󰙿", "Freezing drizzle"),
    "284": ("󰙿", "Heavy freezing drizzle"),
    "293": ("󰼳", "Light rain"),
    "296": ("󰖗", "Light rain"),
    "299": ("󰖗", "Moderate rain"),
    "302": ("󰖗", "Rain"),
    "305": ("󰖖", "Heavy rain"),
    "308": ("󰖖", "Heavy rain"),
    "311": ("󰙿", "Freezing rain"),
    "314": ("󰙿", "Heavy freezing rain"),
    "317": ("󰙿", "Sleet"),
    "320": ("󰙿", "Heavy sleet"),
    "323": ("󰼴", "Light snow"),
    "326": ("󰼴", "Light snow"),
    "329": ("󰖘", "Moderate snow"),
    "332": ("󰖘", "Snow"),
    "335": ("󰼶", "Heavy snow"),
    "338": ("󰼶", "Heavy snow"),
    "350": ("󰙿", "Ice pellets"),
    "353": ("󰼳", "Light shower"),
    "356": ("󰖖", "Heavy shower"),
    "359": ("󰖖", "Torrential rain"),
    "362": ("󰙿", "Sleet showers"),
    "365": ("󰙿", "Heavy sleet showers"),
    "368": ("󰼴", "Snow showers"),
    "371": ("󰼶", "Heavy snow showers"),
    "374": ("󰙿", "Ice pellet showers"),
    "377": ("󰙿", "Heavy ice pellets"),
    "386": ("󰙾", "Thunderstorm"),
    "389": ("󰙾", "Heavy thunderstorm"),
    "392": ("󰙾", "Thundery snow"),
    "395": ("󰙾", "Heavy thundery snow"),
}

WMO_ICONS = {
    0: ("󰖙", "Clear sky"),
    1: ("󰖙", "Mainly clear"),
    2: ("󰖕", "Partly cloudy"),
    3: ("󰖐", "Overcast"),
    45: ("󰖑", "Fog"),
    48: ("󰖑", "Rime fog"),
    51: ("󰼳", "Light drizzle"),
    53: ("󰼳", "Drizzle"),
    55: ("󰼳", "Dense drizzle"),
    56: ("󰙿", "Freezing drizzle"),
    57: ("󰙿", "Freezing drizzle"),
    61: ("󰖗", "Slight rain"),
    63: ("󰖗", "Rain"),
    65: ("󰖖", "Heavy rain"),
    66: ("󰙿", "Freezing rain"),
    67: ("󰙿", "Heavy freezing rain"),
    71: ("󰼴", "Slight snow"),
    73: ("󰖘", "Snow"),
    75: ("󰼶", "Heavy snow"),
    77: ("󰖘", "Snow grains"),
    80: ("󰼳", "Rain showers"),
    81: ("󰖗", "Rain showers"),
    82: ("󰖖", "Violent showers"),
    85: ("󰼴", "Snow showers"),
    86: ("󰼶", "Heavy snow showers"),
    95: ("󰙾", "Thunderstorm"),
    96: ("󰙾", "Thunderstorm with hail"),
    99: ("󰙾", "Thunderstorm with hail"),
}

def day_label(date_str):
    try:
        dt = datetime.date.fromisoformat(date_str)
        if dt == datetime.date.today():
            return "Today"
        return dt.strftime("%a")
    except Exception:
        return date_str[:3]

def fetch_json(url, timeout=5):
    req = urllib.request.Request(url, headers={"User-Agent": "tern-bar/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))

def from_wttr():
    loc = urllib.parse.quote(os.environ.get("TERN_BAR_WEATHER_LOCATION", "").strip())
    base = os.environ.get("TERN_BAR_WEATHER_WTTR_BASE", "https://wttr.in").rstrip("/")
    url = f"{base}/{loc}?format=j1"
    data = fetch_json(url, timeout=5)
    cur = (data.get("current_condition") or [{}])[0]
    code = str(cur.get("weatherCode", "113"))
    icon, default_desc = WWO_ICONS.get(code, ("󰖕", "Clear"))
    desc_list = cur.get("weatherDesc") or []
    desc = (desc_list[0].get("value") if desc_list else "") or default_desc
    temp_c = int(round(float(cur.get("temp_C", 0))))
    feels_c = int(round(float(cur.get("FeelsLikeC", temp_c))))

    forecast = []
    for w in (data.get("weather") or [])[:5]:
        d_str = str(w.get("date", ""))
        hourly = w.get("hourly") or []
        mid = hourly[len(hourly) // 2] if hourly else {}
        w_code = str(mid.get("weatherCode", code))
        w_icon, w_def = WWO_ICONS.get(w_code, (icon, default_desc))
        w_desc_list = mid.get("weatherDesc") or []
        w_desc = (w_desc_list[0].get("value") if w_desc_list else "") or w_def
        max_c = int(round(float(w.get("maxtempC", temp_c))))
        min_c = int(round(float(w.get("mintempC", temp_c))))
        forecast.append({
            "date": d_str,
            "day": day_label(d_str),
            "icon": w_icon,
            "max": f"{max_c}°",
            "min": f"{min_c}°",
            "desc": w_desc.strip(),
        })

    return {
        "temp": f"{temp_c}°C",
        "feelsLike": f"{feels_c}°C",
        "icon": icon,
        "desc": desc.strip(),
        "forecast": forecast,
    }

def from_open_meteo():
    coords = os.environ.get("TERN_BAR_WEATHER_COORDS", "").strip()
    loc = os.environ.get("TERN_BAR_WEATHER_LOCATION", "").strip()
    lat, lon = None, None
    if "," in coords:
        parts = coords.split(",", 1)
        lat, lon = float(parts[0]), float(parts[1])
    elif loc:
        geo_base = os.environ.get(
            "TERN_BAR_WEATHER_GEOCODE_URL",
            "https://geocoding-api.open-meteo.com/v1/search",
        )
        q = urllib.parse.quote(loc)
        geo = fetch_json(f"{geo_base}?name={q}&count=1&format=json", timeout=4)
        first = (geo.get("results") or [{}])[0]
        lat = float(first["latitude"])
        lon = float(first["longitude"])
    else:
        geo_url = os.environ.get("TERN_BAR_WEATHER_GEO_URL", "https://ipwho.is/")
        geo = fetch_json(geo_url, timeout=4)
        lat = float(geo["latitude"])
        lon = float(geo["longitude"])

    meteo_base = os.environ.get(
        "TERN_BAR_WEATHER_METEO_URL",
        "https://api.open-meteo.com/v1/forecast",
    )
    url = (
        f"{meteo_base}?latitude={lat}&longitude={lon}"
        "&current=temperature_2m,apparent_temperature,weather_code"
        "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        "&timezone=auto&forecast_days=5"
    )
    data = fetch_json(url, timeout=5)
    cur = data.get("current") or {}
    wmo = int(cur.get("weather_code", 0))
    icon, desc = WMO_ICONS.get(wmo, ("󰖕", "Clear"))
    temp_c = int(round(float(cur.get("temperature_2m", 0))))
    feels_c = int(round(float(cur.get("apparent_temperature", temp_c))))

    daily = data.get("daily") or {}
    times = daily.get("time") or []
    codes = daily.get("weather_code") or []
    maxs = daily.get("temperature_2m_max") or []
    mins = daily.get("temperature_2m_min") or []

    forecast = []
    for i in range(min(5, len(times))):
        d_code = int(codes[i]) if i < len(codes) else wmo
        d_icon, d_desc = WMO_ICONS.get(d_code, (icon, desc))
        hi = int(round(float(maxs[i]))) if i < len(maxs) else temp_c
        lo = int(round(float(mins[i]))) if i < len(mins) else temp_c
        forecast.append({
            "date": times[i],
            "day": day_label(times[i]),
            "icon": d_icon,
            "max": f"{hi}°",
            "min": f"{lo}°",
            "desc": d_desc,
        })

    return {
        "temp": f"{temp_c}°C",
        "feelsLike": f"{feels_c}°C",
        "icon": icon,
        "desc": desc,
        "forecast": forecast,
    }

result = None
mock = os.environ.get("TERN_BAR_WEATHER_MOCK", "").strip()
if mock:
    try:
        result = json.loads(mock)
    except Exception:
        result = None

if result is None:
    for fn in (from_open_meteo, from_wttr):
        try:
            result = fn()
            if result and result.get("temp"):
                break
        except Exception:
            continue

if result is not None:
    tmp_path = cache_path + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False)
        os.replace(tmp_path, cache_path)
    except Exception:
        pass
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

if os.path.exists(cache_path):
    try:
        with open(cache_path, "r", encoding="utf-8") as f:
            cached = json.loads(f.read())
            if isinstance(cached, dict) and cached.get("temp"):
                print(json.dumps(cached, ensure_ascii=False))
    except Exception:
        pass

sys.exit(1)
PY
