// Current conditions via open-meteo (keyless). Geocodes the configured
// location name once per change, then refreshes every 30 minutes.
// Empty location = service off.
//
// One request carries `current`, today's `daily` block and the hourly series,
// so feels-like, high/low, rain chance and the next twelve hours all arrive
// without a second round trip.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    property real lat: 0
    property real lon: 0
    property bool located: false
    property real temp: 0
    property real feelsLike: 0
    property real high: 0
    property real low: 0
    property int humidity: -1
    property real wind: 0
    property int precipProb: -1
    property string sunrise: ""
    property string sunset: ""
    property bool daylight: true
    property int code: -1
    // Next 12 hours from the current one: { hh, prob, mm, temp }.
    property var hours: []

    // A bar at or above this reads as "it will rain" in the summary line.
    readonly property int rainThreshold: 30
    readonly property bool ready: located && code >= 0
    readonly property string unit: settingsStore.weatherFahrenheit ? "°F" : "°C"
    readonly property string windUnit: settingsStore.weatherFahrenheit ? "mph" : "km/h"
    readonly property string display: ready ? Math.round(temp) + "°" : ""

    // WMO weather code buckets → glyph + label + colour. Clear skies get a
    // moon after sunset; every other bucket looks the same day or night.
    function glyphFor(c, day) {
        if (c === 0) return day ? "󰖙" : "󰖔";          // clear
        if (c <= 2) return day ? "󰖕" : "󰼱";           // partly cloudy
        if (c === 3) return "󰖐";                       // overcast
        if (c <= 48) return "󰖑";                       // fog
        if (c <= 57) return "󰖗";                       // drizzle
        if (c <= 67 || (c >= 80 && c <= 82)) return "󰖖";  // rain
        if (c <= 77 || c === 85 || c === 86) return "󰖘";  // snow
        return "󰖓";                                    // thunder
    }
    function labelFor(c) {
        if (c === 0) return "clear";
        if (c <= 2) return "partly cloudy";
        if (c === 3) return "overcast";
        if (c <= 48) return "fog";
        if (c <= 57) return "drizzle";
        if (c <= 67 || (c >= 80 && c <= 82)) return "rain";
        if (c <= 77 || c === 85 || c === 86) return "snow";
        return "thunderstorm";
    }
    function colorFor(c, day) {
        if (c === 0) return day ? Theme.accent.yellow : Theme.accent.purple;
        if (c <= 2) return day ? Theme.accent.blueBright : Theme.accent.purple;
        if (c <= 48) return Theme.accent.slate;        // overcast + fog
        if (c <= 57) return Theme.accent.teal;         // drizzle
        if (c <= 67 || (c >= 80 && c <= 82)) return Theme.accent.blue;
        if (c <= 77 || c === 85 || c === 86) return Theme.accent.blueBright;
        return Theme.accent.purple;                    // thunder
    }
    readonly property string glyph: ready ? glyphFor(code, daylight) : ""
    readonly property string label: ready ? labelFor(code) : ""
    readonly property color accent: ready ? colorFor(code, daylight) : Theme.muted

    // Warm-to-cool ramp for the reading itself, so a glance at the colour
    // says as much as reading the number.
    function tempColor(t) {
        const c = settingsStore.weatherFahrenheit ? (t - 32) * 5 / 9 : t;
        if (c <= 0)  return Theme.accent.blueBright;
        if (c <= 10) return Theme.accent.blue;
        if (c <= 18) return Theme.accent.teal;
        if (c <= 25) return Theme.accent.green;
        if (c <= 30) return Theme.accent.orange;
        return Theme.accent.red;
    }

    // Contiguous runs of hours at or above the threshold. An hour's bar covers
    // the hour it starts, so a run of 16,17,18 ends at 19:00.
    function rainWindows() {
        const out = [];
        let start = -1;
        for (let i = 0; i < hours.length; i++) {
            const wet = hours[i].prob >= rainThreshold;
            if (wet && start < 0) start = i;
            if (!wet && start >= 0) { out.push([start, i]); start = -1; }
        }
        if (start >= 0) out.push([start, hours.length]);
        return out;
    }
    function _span(w) {
        const from = hours[w[0]].hh + ":00";
        // One past the last wet hour. A run that reaches the end of the
        // series has no known end, so it is left open rather than guessed.
        if (w[1] >= hours.length) return "from " + from;
        return from + "–" + hours[w[1]].hh + ":00";
    }
    readonly property string rainSummary: {
        if (!ready || hours.length === 0) return "";
        const w = rainWindows();
        if (w.length === 0) return "No rain in the next 12 h";
        let peak = 0;
        for (const h of hours) peak = Math.max(peak, h.prob);
        const spans = w.length === 1 ? _span(w[0])
            : w.length === 2 ? _span(w[0]) + " and " + _span(w[1])
            : _span(w[0]) + " and " + (w.length - 1) + " more";
        return "Rain " + spans + " · peak " + peak + "%";
    }
    readonly property int peakHour: {
        let idx = -1, best = 0;
        for (let i = 0; i < hours.length; i++)
            if (hours[i].prob > best) { best = hours[i].prob; idx = i; }
        return idx;
    }

    // Re-geocode whenever the location setting changes.
    property string _lastLocation: ""
    function checkLocation() {
        const loc = settingsStore.weatherLocation.trim();
        if (loc === _lastLocation) return;
        _lastLocation = loc;
        located = false;
        code = -1;
        if (loc !== "") { geoProc.running = false; geoProc.running = true; }
    }
    Connections {
        target: settingsStore
        function onWeatherLocationChanged() { svc.checkLocation() }
    }
    Component.onCompleted: checkLocation()

    Process {
        id: geoProc
        command: ["curl", "-fsSL", "--max-time", "10",
            "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
            + encodeURIComponent(settingsStore.weatherLocation.trim())]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // curl writes nothing when the network is down; parsing that
                // only produces log noise, so treat it as "not now".
                if (text.trim() === "") return;
                try {
                    const r = JSON.parse(text).results;
                    if (r && r.length > 0) {
                        svc.lat = r[0].latitude;
                        svc.lon = r[0].longitude;
                        svc.located = true;
                        fetchProc.running = false;
                        fetchProc.running = true;
                    }
                } catch (e) { console.warn("weather geocode failed:", e); }
            }
        }
    }

    Process {
        id: fetchProc
        command: ["curl", "-fsSL", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + svc.lat
            + "&longitude=" + svc.lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m"
            + ",wind_speed_10m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + ",precipitation_probability_max,sunrise,sunset"
            + "&hourly=temperature_2m,precipitation_probability"
            + "&timezone=auto&forecast_days=2"
            + "&temperature_unit=" + (settingsStore.weatherFahrenheit ? "fahrenheit" : "celsius")
            + "&wind_speed_unit=" + (settingsStore.weatherFahrenheit ? "mph" : "kmh")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") return;
                try {
                    const j = JSON.parse(text);
                    const c = j.current;
                    svc.temp = c.temperature_2m;
                    svc.feelsLike = c.apparent_temperature;
                    svc.humidity = c.relative_humidity_2m;
                    svc.wind = c.wind_speed_10m;
                    svc.daylight = c.is_day === 1;
                    // Set last: `code` is what flips `ready`, so everything
                    // the card reads is already in place when it turns on.
                    svc.code = c.weather_code;

                    // Start at the hour we are in, so the strip always reads
                    // left-to-right from now.
                    const hr = j.hourly;
                    if (hr && hr.time) {
                        const key = Qt.formatDateTime(new Date(), "yyyy-MM-ddTHH:00");
                        let at = hr.time.indexOf(key);
                        if (at < 0) at = 0;
                        const out = [];
                        for (let i = at; i < Math.min(at + 12, hr.time.length); i++)
                            out.push({
                                hh: String(hr.time[i]).slice(11, 13),
                                prob: hr.precipitation_probability[i],
                                temp: hr.temperature_2m[i]
                            });
                        svc.hours = out;
                    }

                    const d = j.daily;
                    if (d && d.time && d.time.length > 0) {
                        svc.high = d.temperature_2m_max[0];
                        svc.low = d.temperature_2m_min[0];
                        svc.precipProb = d.precipitation_probability_max[0];
                        svc.sunrise = String(d.sunrise[0]).slice(11, 16);
                        svc.sunset = String(d.sunset[0]).slice(11, 16);
                    }
                } catch (e) { console.warn("weather fetch failed:", e); }
            }
        }
    }
    Timer {
        running: svc.located
        interval: 1800000   // 30 min
        repeat: true
        onTriggered: { fetchProc.running = false; fetchProc.running = true; }
    }
    // Refetch in the new unit when it flips.
    Connections {
        target: settingsStore
        function onWeatherFahrenheitChanged() {
            if (svc.located) { fetchProc.running = false; fetchProc.running = true; }
        }
    }
}
