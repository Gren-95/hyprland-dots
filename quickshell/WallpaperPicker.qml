// Wallpaper picker modal: grid of thumbnails for files in
// $HOME/Pictures/wallpapers. Click → apply via scripts/wallpaper.sh.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool open: false
    property var wallpapers: []   // array of absolute paths
    // Default anchor set from the bar (the Quick Actions chevron); openers
    // can pass their own item via toggle(from) so the flyout hangs under
    // whatever was actually clicked (QA tile, promoted icon).
    property var anchorBar: null
    property var anchorItem: null
    property Item _openAnchor: null

    function toggle(from) {
        open = !open;
        if (open) _openAnchor = from ?? null;
    }
    function close()  { open = false }
    function refresh() { if (!listProc.running) listProc.running = true }

    onOpenChanged: if (open) refresh()

    Process {
        id: listProc
        command: ["sh", "-c",
            "find " + settingsStore.wallpaperDir + " -type f \\( " +
            "-iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' \\) | sort"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpapers = text.trim().split("\n").filter(s => s.length > 0);
            }
        }
    }

    Process { id: setProc; command: [] }
    function apply(path) {
        setProc.command = ["bash", Quickshell.env("HOME") + "/.config/scripts/wallpaper.sh", path];
        setProc.startDetached();
        close();
    }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root._openAnchor ?? root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("wallpaper", "w", 560)
        cardHeight: settingsStore.flyoutSize("wallpaper", "h", 560)
        onDismissed: root.close()
        Item {
                anchors.fill: parent
                ColumnLayout {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: Theme.spacing.lg
                    }
                    spacing: Theme.spacing.md

                    Text {
                        Layout.fillWidth: true
                        text: "Wallpaper"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: -4
                        text: root.wallpapers.length + " IMAGES"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.letterSpacing: 1
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.preferredHeight: 440
                        contentWidth: width
                        contentHeight: grid.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // Reset to the top whenever the picker reopens, so
                        // users don't reappear at their last scroll position.
                        Connections {
                            target: root
                            function onOpenChanged() { if (root.open) flick.contentY = 0; }
                        }

                        GridLayout {
                            id: grid
                            width: parent.width
                            columns: 3
                            columnSpacing: Theme.spacing.md
                            rowSpacing: Theme.spacing.md

                            Repeater {
                                model: root.wallpapers
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 140
                                    radius: 10
                                    color: Theme.bgDeep
                                    border.color: hover.containsMouse ? Theme.accentPrimary : Theme.borderSubtle
                                    border.width: hover.containsMouse ? 2 : 1
                                    clip: true
                                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: "file://" + tile.modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 320
                                        sourceSize.height: 180
                                    }

                                    Rectangle {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            bottom: parent.bottom
                                            margins: 2
                                        }
                                        height: 22
                                        color: "#cc000000"
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            text: tile.modelData.split("/").pop()
                                            color: Theme.fg
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.xs
                                            elide: Text.ElideMiddle
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    MouseArea {
                                        id: hover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.apply(tile.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }
}
