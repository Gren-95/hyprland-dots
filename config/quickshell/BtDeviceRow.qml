// One Bluetooth device as a card row: icon bubble, name with a state line,
// battery pill, and a settings button that opens the device in the settings
// app (rename, forget, AirPods codec and audio fix live there). A paired
// device toggles its connection on click; an `available` (unpaired,
// discovered) device pairs and connects on click. Connected AirPods show
// their noise control under the row.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: dr
    property var device
    property bool highlighted: false
    property bool available: false
    signal hovered()
    function openSettings() {
        Cmd.run([Paths.home + "/.local/bin/settings", "-p", "bluetooth"]);
    }

    readonly property bool isConnected: !!device && device.connected
    readonly property bool isAirPods: !!device && /airpods/i.test(device.name || device.deviceName || "")
    readonly property bool isPairing: !!device && device.pairing
    // BlueZ reports no battery for AirPods; AirPodsBattery fills that gap.
    readonly property real airPodsLevel: device ? AirPodsBattery.levelFor(device.address) : -1
    readonly property real batteryLevel: device && device.batteryAvailable ? device.battery : airPodsLevel
    readonly property string iconName: device && device.icon ? device.icon : ""
    readonly property string kindGlyph: {
        const n = iconName;
        if (n.indexOf("headset") >= 0 || n.indexOf("headphone") >= 0) return "󰋋";
        if (n.indexOf("speaker") >= 0 || n.indexOf("audio") >= 0) return "󰓃";
        if (n.indexOf("keyboard") >= 0) return "󰌌";
        if (n.indexOf("mouse") >= 0) return "󰍽";
        if (n.indexOf("phone") >= 0) return "󰏲";
        if (n.indexOf("computer") >= 0 || n.indexOf("laptop") >= 0) return "󰇄";
        if (n.indexOf("gaming") >= 0 || n.indexOf("joystick") >= 0) return "󰖺";
        return isConnected ? "󰂱" : "󰂯";
    }
    readonly property string stateText: isPairing ? "Pairing…"
        : isConnected ? "Connected"
        : available ? "Click to pair"
        : "Paired"
    readonly property color stateColor: isPairing ? Theme.accent.yellow
        : isConnected ? Theme.accent.green
        : Theme.muted

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight
    radius: 10 * Theme.radiusScale
    clip: true
    color: highlighted ? Theme.bgActive : (rowMa.containsMouse ? Theme.bgHover : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ----- Main row -----
        Item {
            id: main
            Layout.fillWidth: true
            implicitHeight: 60
            scale: rowMa.pressed ? 0.985 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

            // Selection / connected accent rail.
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height - 18
                radius: 1.5 * Theme.radiusScale
                color: Theme.accent.blueBright
                opacity: dr.isConnected ? 1.0 : (dr.highlighted ? 0.8 : 0.0)
                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing.lg
                anchors.rightMargin: Theme.spacing.md
                spacing: Theme.spacing.lg

                // Icon bubble
                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: width / 2
                    color: dr.isConnected ? Theme.alpha(Theme.accent.blue, 0.2) : Theme.bgInset
                    border.color: dr.isConnected ? Theme.accent.blue : Theme.borderStrong
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                    Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }
                    Text {
                        anchors.centerIn: parent
                        text: dr.kindGlyph
                        color: dr.isConnected ? Theme.accent.blueBright : Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                    }
                    // Soft pulse while connecting.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: Theme.accent.yellow
                        border.width: 2
                        opacity: 0
                        visible: dr.isPairing
                        SequentialAnimation on opacity {
                            running: dr.isPairing
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.8; to: 0.0; duration: 900; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // Name + state
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: dr.device ? (dr.device.name || dr.device.deviceName || dr.device.address) : ""
                        textFormat: Text.PlainText   // external text: never render markup
                        color: dr.isConnected ? Theme.fg : Theme.fgMuted
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: dr.isConnected
                    }
                    RowLayout {
                        spacing: Theme.spacing.sm
                        Rectangle {
                            id: stateDot
                            visible: dr.isConnected || dr.isPairing
                            width: 6; height: 6; radius: 3
                            color: dr.stateColor
                            SequentialAnimation on opacity {
                                running: dr.isPairing
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.25; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            text: dr.stateText
                            color: dr.stateColor
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                        }
                    }
                }

                // Battery pill
                Rectangle {
                    visible: dr.isConnected && dr.batteryLevel >= 0 && !dr.isPairing
                    readonly property real level: Math.max(0, dr.batteryLevel)
                    readonly property color levelColor: level <= 0.2 ? Theme.accent.red
                        : level <= 0.4 ? Theme.accent.orange : Theme.accent.green
                    implicitWidth: batRow.implicitWidth + 16
                    implicitHeight: 26
                    radius: height / 2
                    color: Theme.alpha(levelColor, 0.14)
                    border.color: Theme.alpha(levelColor, 0.4)
                    border.width: 1
                    RowLayout {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.sm
                        Rectangle {
                            implicitWidth: 22; implicitHeight: 10
                            radius: 3
                            color: "transparent"
                            border.color: parent.parent.levelColor
                            border.width: 1
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.margins: 1.5
                                width: Math.max(0, (parent.width - 3) * parent.parent.parent.level)
                                radius: 2
                                color: parent.parent.parent.levelColor
                                Behavior on width { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                            }
                        }
                        Text {
                            text: Math.round(parent.parent.level * 100) + "%"
                            color: parent.parent.levelColor
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }
                }

                Spinner {
                    visible: dr.isPairing
                    color: Theme.accent.yellow
                    implicitWidth: 16
                    implicitHeight: 16
                }

                // Settings button (paired devices only): the device in the
                // settings app. A gear rather than a chevron: the row itself
                // toggles the connection.
                Rectangle {
                    visible: !dr.available
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 8 * Theme.radiusScale
                    color: chevMa.containsMouse ? Theme.bgActive : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: chevMa.containsMouse ? Theme.accentPrimary : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    }
                    MouseArea {
                        id: chevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dr.openSettings()
                    }
                }
            }

            MouseArea {
                id: rowMa
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (!dr.device) return;
                    if (e.button === Qt.RightButton) { dr.openSettings(); return; }
                    if (dr.available) {
                        dr.device.trusted = true;
                        dr.device.pair();
                    } else if (dr.device.connected) dr.device.disconnect();
                    else dr.device.connect();
                }
                onContainsMouseChanged: if (containsMouse) dr.hovered()
            }
        }

        // ----- AirPods noise control, while connected -----
        AirPodsControls {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing.lg
            Layout.rightMargin: Theme.spacing.lg
            Layout.bottomMargin: Theme.spacing.md
            visible: dr.isAirPods && dr.isConnected && live
            device: dr.device
        }
    }
}
