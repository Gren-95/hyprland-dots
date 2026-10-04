// One clipboard history entry: id, thumbnail / colour swatch / text preview,
// and a delete button that appears on the highlighted row. The selection plate
// is drawn by the list (LauncherSelection).
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: row
    property var entry
    property bool highlighted: false
    property string thumbDir: "/tmp/cliphist-thumbs"
    signal picked()
    signal hovered()
    signal removed()

    readonly property bool showThumb: !!(row.entry && row.entry.isImage && settingsStore.clipboardThumbs)
    readonly property string thumbPath: row.entry && row.entry.isImage
        ? row.thumbDir + "/" + row.entry.id + "." + row.entry.ext
        : ""
    property bool thumbReady: false

    implicitHeight: row.showThumb ? 84 : 56
    scale: rowMa.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    Process {
        id: thumbProc
        running: false
        command: row.entry && row.entry.isImage
            ? ["sh", "-c",
               "mkdir -p \"$1\" && if [ ! -s \"$1/$2.$3\" ]; then printf '%s\\n' \"$4\" | cliphist decode > \"$1/$2.$3\"; fi",
               "_", row.thumbDir, row.entry.id, row.entry.ext, row.entry.raw]
            : []
        onExited: row.thumbReady = true
    }
    Component.onCompleted: {
        if (row.showThumb) thumbProc.running = true;
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) row.removed();
            else row.picked();
        }
        onContainsMouseChanged: if (containsMouse) row.hovered()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.xl
        anchors.rightMargin: Theme.spacing.lg
        spacing: Theme.spacing.lg

        Text {
            text: row.entry ? row.entry.id : ""
            color: row.highlighted ? Theme.accentPrimary : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }

        Rectangle {
            visible: row.showThumb
            Layout.preferredWidth: 96
            Layout.preferredHeight: 68
            radius: 6 * Theme.radiusScale
            color: Theme.bgDeep
            border.color: Theme.borderStrong
            border.width: 1
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: 2
                source: row.thumbReady && row.thumbPath ? "file://" + row.thumbPath : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }
            }
        }

        Rectangle {
            visible: !!(row.entry && row.entry.isColor)
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 8 * Theme.radiusScale
            color: row.entry && row.entry.isColor ? row.entry.color : "transparent"
            border.color: Theme.borderStrong
            border.width: 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: row.entry ? row.entry.preview : ""
                color: row.highlighted ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
                font.bold: row.highlighted
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
            Text {
                Layout.fillWidth: true
                visible: row.showThumb
                text: row.entry && row.entry.isImage
                    ? (row.entry.dims ? row.entry.dims + "  •  " + row.entry.size : row.entry.size)
                    : ""
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
            }
        }

        Text {
            text: "↵"
            color: Theme.accentPrimary
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            opacity: row.highlighted ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
        }

        Rectangle {
            id: delBtn
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 8 * Theme.radiusScale
            enabled: row.highlighted
            opacity: row.highlighted ? 1.0 : 0.0
            scale: delMa.pressed ? 0.9 : 1.0
            color: delMa.containsMouse ? Theme.accent.redDeep : "transparent"
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Text {
                anchors.centerIn: parent
                text: "󰩺"
                color: delMa.containsMouse ? Theme.fg : Theme.accent.redSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
            }
            MouseArea {
                id: delMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: delBtn.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: row.removed()
            }
        }
    }
}
