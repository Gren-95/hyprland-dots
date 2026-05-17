import QtQuick
import QtQuick.Layouts

Rectangle {
    id: wr
    property var network
    property bool highlighted: false
    signal hovered()
    signal picked()
    signal forgetRequested()
    Layout.fillWidth: true
    implicitHeight: Theme.height.rowSm
    radius: 6
    color: wr.highlighted ? "#3b3531" : (wHover.containsMouse ? Theme.bgAlt : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

    readonly property bool isConnected: wr.network && wr.network.connected
    readonly property bool isKnown: wr.network && wr.network.known
    readonly property bool isBusy: wr.network && wr.network.stateChanging

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: Theme.spacing.md
        Text {
            text: wr.isConnected ? "󰖩" : (wr.isKnown ? "󰤨" : "󰖪")
            color: wr.isConnected ? Theme.accent.green : (wr.isKnown ? Theme.muted : Theme.mutedDeep)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            Layout.fillWidth: true
            text: wr.network ? (wr.network.name || "<hidden>") : ""
            color: "#f5f5f4"
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: wr.isConnected
        }
        Text {
            visible: wr.isBusy
            text: "…"
            color: Theme.accent.yellow
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
        Text {
            visible: wr.isKnown && !wr.isConnected && !wr.isBusy
            text: "saved"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
        }
        Text {
            visible: wr.isConnected
            text: "✓"
            color: Theme.accent.green
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    MouseArea {
        id: wHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!wr.network) return;
            if (e.button === Qt.RightButton && wr.network.known) {
                wr.forgetRequested();
                return;
            }
            wr.picked();
        }
        onContainsMouseChanged: if (containsMouse) wr.hovered()
    }
}
