import QtQuick
import QtQuick.Layouts

Rectangle {
    id: vrow
    property var entry
    property bool isExitNode: false
    property bool highlighted: false
    signal copied()
    signal exitToggled()
    signal hovered()
    Layout.fillWidth: true
    implicitHeight: Theme.height.row
    radius: Theme.radius.sm

    readonly property bool isOnline: vrow.entry && vrow.entry.online

    color: vrow.highlighted ? Theme.bgActive : (vrowMa.containsMouse ? Theme.bgHover : "transparent")
    border.color: vrow.isExitNode ? Theme.accent.purple : "transparent"
    border.width: vrow.isExitNode ? 1 : 0
    scale: vrowMa.pressed ? 0.985 : 1.0
    Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Animated selection / hover accent rail.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 14
        radius: 1.5 * Theme.radiusScale
        color: Theme.accent.purple
        opacity: vrow.highlighted ? 0.9 : (vrowMa.containsMouse ? 0.4 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }

    // Full-row click target sits BELOW the interactive children so the
    // exit-node toggle actually receives its own clicks.
    MouseArea {
        id: vrowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: vrow.copied()
        onContainsMouseChanged: if (containsMouse) vrow.hovered()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: Theme.spacing.md

        // Online status dot with a soft pulsing halo.
        Item {
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            Layout.alignment: Qt.AlignVCenter
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4 * Theme.radiusScale
                color: Theme.accent.green
                visible: vrow.isOnline
                opacity: 0.0
                SequentialAnimation on opacity {
                    running: vrow.isOnline
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.5; to: 0.0; duration: 1500; easing.type: Easing.OutQuad }
                    PauseAnimation { duration: 250 }
                }
                SequentialAnimation on scale {
                    running: vrow.isOnline
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 2.4; duration: 1500; easing.type: Easing.OutQuad }
                    PauseAnimation { duration: 250 }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4 * Theme.radiusScale
                color: vrow.isOnline ? Theme.accent.green : Theme.disabled
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: vrow.entry ? vrow.entry.host : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: vrow.isOnline
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: vrow.entry && vrow.entry.ips.length > 0 ? vrow.entry.ips[0] : ""
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                elide: Text.ElideRight
            }
        }
        Rectangle {
            visible: vrow.entry && vrow.entry.exitNodeOption
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            radius: 11 * Theme.radiusScale
            color: vrow.isExitNode ? Theme.accent.purple : "transparent"
            border.color: vrow.isExitNode ? Theme.accent.purple : Theme.border
            border.width: 1
            scale: exitMa.pressed ? 0.88 : 1.0
            Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
            Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
            Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Text {
                anchors.centerIn: parent
                text: "↗"
                color: vrow.isExitNode ? "#0a0a0a" : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: true
            }
            MouseArea {
                id: exitMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: vrow.exitToggled()
            }
        }
        Text {
            text: "󰆏"
            color: vrowMa.containsMouse ? Theme.muted : Theme.border
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
    }
}
