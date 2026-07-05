// Current conditions via open-meteo (keyless). Geocodes the configured
// location name once per change, then refreshes temperature + WMO code
// every 30 minutes. Empty location = service off.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    property real lat: 0
    property real lon: 0
    property bool located: false
    property real temp: 0
    property int code: -1
    readonly property bool ready: located && code >= 0
    readonly property string unit: settingsStore.weatherFahrenheit ? "°F" : "°C"
    readonly property string display: ready ? Math.round(temp) + "°" : ""

    // WMO weather code buckets → glyph + label.
    function glyphFor(c) {
        if (c === 0) return "󰖙";                     // clear
        if (c <= 2) return "󰖕";                      // partly cloudy
        if (c === 3) return "󰖐";                     // overcast
        if (c <= 48) return "󰖑";                     // fog
        if (c <= 57) return "󰖗";                     // drizzle
        if (c <= 67 || (c >= 80 && c <= 82)) return "󰖖";  // rain
        if (c <= 77 || c === 85 || c === 86) return "󰖘";  // snow
        return "󰖓";                                  // thunder
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
    readonly property string glyph: ready ? glyphFor(code) : ""
    readonly property string label: ready ? labelFor(code) : ""

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
            + "&current=temperature_2m,weather_code"
            + "&temperature_unit=" + (settingsStore.weatherFahrenheit ? "fahrenheit" : "celsius")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).current;
                    svc.temp = c.temperature_2m;
                    svc.code = c.weather_code;
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
