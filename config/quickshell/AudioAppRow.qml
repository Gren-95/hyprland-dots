// One playback stream (an app) in the Sound popup, drawn as a VolumeLine:
// the app's icon (click to mute), its name and what it is playing, a slider.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

VolumeLine {
    id: row
    property var node
    // Read through `ready`: the properties fill in only once the tracker has
    // bound the node, and the binding has to see that change to update.
    readonly property var props: node && node.ready && node.properties ? node.properties : ({})
    readonly property string appName: props["application.name"] || (node ? node.nickname || node.name : "") || "Unknown"
    readonly property string binary: String(props["application.process.binary"] || "")

    // Icon name: what the stream names, else the app's desktop entry icon,
    // else its binary. scripts/icon-path.sh turns it into a file in the icon
    // theme; the glyph shows when there is none.
    readonly property string iconName: {
        const entry = DesktopEntries.heuristicLookup(binary || appName);
        return String(props["application.icon_name"] || (entry && entry.icon) || binary || "");
    }
    property string iconFile: ""
    onIconNameChanged: if (iconName !== "") { iconProc.running = false; iconProc.running = true; }
    Process {
        id: iconProc
        command: ["bash", Paths.scripts + "/icon-path.sh", row.iconName]
        stdout: StdioCollector { onStreamFinished: row.iconFile = text.trim() }
    }
    iconSource: iconFile !== "" ? "file://" + iconFile : ""

    label: appName
    sublabel: {
        const t = props["media.name"] || "";
        return t === appName ? "" : t;
    }
    glyph: "󰎆"
    volume: node && node.audio ? node.audio.volume : 0
    muted: !!(node && node.audio && node.audio.muted)
    accent: Theme.accent.purple
    onMoved: (value) => { if (row.node && row.node.audio) row.node.audio.volume = value; }
    onMuteToggled: { if (row.node && row.node.audio) row.node.audio.muted = !row.node.audio.muted; }
}
